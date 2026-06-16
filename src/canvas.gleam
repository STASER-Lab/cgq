import gleam/bool
import gleam/erlang/process
import gleam/float
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/option
import gleam/result

pub type Canvas {
  Canvas(domain: String, token: String)
}

pub type Error {
  FailedToMakeRequest
  FailedToSendRequest(httpc.HttpError)
  FailedToParseJson(json.DecodeError)
  FailedRequestStatus(Int)
}

pub fn error_summary(error error: Error) -> String {
  case error {
    FailedToMakeRequest -> "the request URL could not be built"
    FailedToSendRequest(_) -> "Canvas could not be reached"
    FailedToParseJson(_) -> "Canvas returned a response in an unexpected format"
    FailedRequestStatus(status) -> status_summary(status)
  }
}

pub fn error_hint(error error: Error) -> option.Option(String) {
  case error {
    FailedToMakeRequest ->
      option.Some("Check that CANVAS_API_DOMAIN is a valid URL.")
    FailedToSendRequest(_) ->
      option.Some("Check CANVAS_API_DOMAIN and your network connection.")
    FailedToParseJson(_) -> option.None
    FailedRequestStatus(status) -> status_hint(status)
  }
}

fn status_summary(status status: Int) -> String {
  case status {
    401 -> "Canvas rejected the API token (401)"
    403 -> "Canvas denied permission for this request (403)"
    404 -> "the requested item was not found (404)"
    422 -> "Canvas rejected the request as invalid (422)"
    429 -> "Canvas rate limited the request (429)"
    status if status >= 500 ->
      "Canvas had a server error (" <> int.to_string(status) <> ")"
    status ->
      "Canvas returned an unexpected status (" <> int.to_string(status) <> ")"
  }
}

fn status_hint(status status: Int) -> option.Option(String) {
  case status {
    401 -> option.Some("Check that CANVAS_API_TOKEN holds a valid token.")
    403 -> option.Some("The token may not have access to this course.")
    404 -> option.Some("Check the course, group, or quiz id.")
    429 -> option.Some("Wait a moment and run the command again.")
    _ -> option.None
  }
}

pub fn new(domain domain: String, token token: String) -> Canvas {
  Canvas(domain:, token:)
}

pub fn request(
  canvas canvas: Canvas,
  endpoint endpoint: String,
) -> Result(request.Request(String), Error) {
  use req <- result.map(
    { canvas.domain <> "/" <> endpoint }
    |> request.to
    |> result.replace_error(FailedToMakeRequest),
  )

  req
  |> request.prepend_header("Authorization", "Bearer " <> canvas.token)
  |> request.set_header("Content-Type", "application/x-www-form-urlencoded")
}

pub fn send(req request: request.Request(String)) -> Result(String, Error) {
  do_make_request(request:, attempt: 1)
}

const base_delay = 1000

const max_attempts = 5

fn do_make_request(
  request request: request.Request(String),
  attempt attempt: Int,
) -> Result(String, Error) {
  let res = {
    use resp <- result.try(
      request
      |> httpc.send
      |> result.map_error(FailedToSendRequest),
    )

    use <- bool.guard(
      when: resp.status >= 300 || resp.status < 200,
      return: resp.status
        |> FailedRequestStatus
        |> Error,
    )

    resp.body |> Ok
  }

  case res {
    Ok(value) -> Ok(value)
    Error(error) ->
      case attempt >= max_attempts || !is_retryable(error) {
        True -> Error(error)
        False -> {
          process.sleep(backoff_milliseconds(attempt))
          do_make_request(request:, attempt: attempt + 1)
        }
      }
  }
}

fn is_retryable(error error: Error) -> Bool {
  case error {
    FailedToSendRequest(_) -> True
    FailedRequestStatus(429) -> True
    FailedRequestStatus(status) -> status >= 500
    FailedToMakeRequest -> False
    FailedToParseJson(_) -> False
  }
}

fn backoff_milliseconds(attempt attempt: Int) -> Int {
  let assert Ok(factor) = int.power(2, int.to_float(attempt))
  float.round(factor) * base_delay
}
