import gleam/bool
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/result

import canvas/canvas

pub type User {
  User(id: Int, name: String)
}

pub fn decoder() -> decode.Decoder(User) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  decode.success(User(id:, name:))
}

pub fn get_user(
  canvas: canvas.Canvas,
  user_id user_id: Int,
) -> Result(User, canvas.Error) {
  let endpoint = "users/" <> int.to_string(user_id)

  use req <- result.try(
    canvas
    |> canvas.request(endpoint),
  )

  use resp <- result.try(
    req
    |> request.set_method(http.Get)
    |> httpc.send
    |> result.map_error(canvas.FailedToSendRequest),
  )

  use <- bool.guard(
    resp.status != 200,
    resp.status |> canvas.FailedRequestStatus |> Error,
  )

  resp.body
  |> json.parse(using: decoder())
  |> result.map_error(canvas.FailedToParseJson)
}
