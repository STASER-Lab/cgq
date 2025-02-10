import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result

import canvas

pub type User {
  User(id: Int, name: String)
}

pub fn decoder() -> decode.Decoder(User) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  decode.success(User(id:, name:))
}

pub fn get_user(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  user_id user_id: Int,
) -> Result(User, canvas.Error) {
  let endpoint =
    "courses/"
    <> int.to_string(course_id)
    <> "/users/"
    <> int.to_string(user_id)

  use req <- result.try(
    canvas
    |> canvas.request(endpoint),
  )

  use res <- result.try(canvas.send(canvas:, req:))

  res
  |> json.parse(using: decoder())
  |> result.map_error(canvas.FailedToParseJson)
}
