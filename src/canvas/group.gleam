import gleam/bool
import gleam/dynamic/decode
import gleam/httpc
import gleam/int
import gleam/json
import gleam/result

import canvas
import canvas/user

pub type Group {
  Group(id: Int, members_count: Int, name: String)
}

fn decoder() -> decode.Decoder(Group) {
  use id <- decode.field("id", decode.int)
  use members_count <- decode.field("members_count", decode.int)
  use name <- decode.field("name", decode.string)
  decode.success(Group(id:, members_count:, name:))
}

pub fn list_groups(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
) -> Result(List(Group), canvas.Error) {
  let endpoint = "courses/" <> int.to_string(course_id) <> "/groups"

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use res <- result.try(
    req
    |> httpc.send
    |> result.map_error(canvas.FailedToSendRequest),
  )

  use <- bool.guard(
    res.status != 200,
    res.status |> canvas.FailedRequestStatus |> Error,
  )

  res.body
  |> json.parse(using: decode.list(decoder()))
  |> result.map_error(canvas.FailedToParseJson)
}

pub fn list_group_users(canvas canvas: canvas.Canvas, group_id group_id: Int) {
  let endpoint = "groups/" <> int.to_string(group_id) <> "/users"

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use res <- result.try(
    req
    |> httpc.send
    |> result.map_error(canvas.FailedToSendRequest),
  )

  use <- bool.guard(
    res.status != 200,
    res.status |> canvas.FailedRequestStatus |> Error,
  )

  res.body
  |> json.parse(using: decode.list(user.decoder()))
  |> result.map_error(canvas.FailedToParseJson)
}
