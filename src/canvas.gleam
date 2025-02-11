import gleam/bool
import gleam/erlang/process
import gleam/float
import gleam/http
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
  MaxRetriesExceeded
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

pub fn send(
  canvas canvas: Canvas,
  req request: request.Request(String),
) -> Result(String, Error) {
  do_make_request(canvas:, request:, attempt: 1)
}

const base_delay = 1000

const max_attempts = 5

fn do_make_request(
  canvas canvas: Canvas,
  request request: request.Request(String),
  attempt attempt: Int,
) {
  let assert Ok(value) = int.power(2, int.to_float(attempt))
  let delay = float.round(value) * base_delay

  let res = {
    use resp <- result.try(
      request
      |> request.set_method(http.Get)
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

  case res, attempt > max_attempts {
    Ok(value), _ -> Ok(value)
    _, True -> Error(MaxRetriesExceeded)
    Error(_), False -> {
      process.sleep(delay)
      do_make_request(canvas:, request:, attempt: attempt + 1)
    }
  }
}
