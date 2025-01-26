import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/result

pub type Canvas {
  Canvas(domain: String, token: String)
}

pub type Error {
  Any
  FailedToMakeRequest
  FailedToSendRequest(httpc.HttpError)
  FailedToParseJson(json.DecodeError)
  FailedRequestStatus(Int)
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
