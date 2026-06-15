import gleam/bool
import gleam/erlang/process
import gleam/float
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
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

/// A human-readable, actionable description of a Canvas failure, for the CLI to
/// print instead of an inspected ADT.
pub fn error_message(error error: Error) -> String {
  case error {
    FailedToMakeRequest ->
      "could not build the request URL (check CANVAS_API_DOMAIN)"
    FailedToSendRequest(_) ->
      "could not reach Canvas (check CANVAS_API_DOMAIN and your network)"
    FailedToParseJson(_) -> "Canvas returned a response in an unexpected format"
    FailedRequestStatus(status) -> status_message(status)
  }
}

fn status_message(status status: Int) -> String {
  case status {
    401 -> "Canvas rejected the API token (401) — check CANVAS_API_TOKEN"
    403 -> "permission denied (403) — the token may lack access to this course"
    404 -> "not found (404) — check the course / group / quiz id"
    422 -> "Canvas rejected the request as invalid (422)"
    429 -> "rate limited by Canvas (429) — try again shortly"
    status if status >= 500 ->
      "Canvas had a server error (" <> int.to_string(status) <> ")"
    status ->
      "Canvas returned an unexpected status (" <> int.to_string(status) <> ")"
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

/// Only transient failures are worth retrying. Client errors like 401/403/404
/// will never succeed on retry, so they surface immediately instead of stalling
/// behind five rounds of backoff.
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
