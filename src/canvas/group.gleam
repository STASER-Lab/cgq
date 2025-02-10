import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
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
  loop_list_groups(canvas:, course_id:, page: 1, groups: [])
}

fn loop_list_groups(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  page page: Int,
  groups acc: List(Group),
) -> Result(List(Group), canvas.Error) {
  io.println("Fetching groups from page " <> int.to_string(page) <> "...")

  let endpoint =
    "courses/"
    <> int.to_string(course_id)
    <> "/groups?page="
    <> int.to_string(page)

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use res <- result.try(canvas.send(canvas:, req:))

  let res =
    res
    |> json.parse(using: decode.list(decoder()))
    |> result.map_error(canvas.FailedToParseJson)

  use groups <- result.try(res)

  use <- bool.guard(groups |> list.is_empty, acc |> Ok)

  let groups = list.append(acc, groups)
  loop_list_groups(canvas:, course_id:, page: page + 1, groups:)
}

pub fn get_group(
  canvas canvas: canvas.Canvas,
  group_id group_id: Int,
) -> Result(Group, canvas.Error) {
  let endpoint = "groups/" <> int.to_string(group_id)

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use res <- result.try(canvas.send(canvas:, req:))

  res
  |> json.parse(using: decoder())
  |> result.map_error(canvas.FailedToParseJson)
}

pub fn list_group_users(canvas canvas: canvas.Canvas, group_id group_id: Int) {
  let endpoint = "groups/" <> int.to_string(group_id) <> "/users"

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use res <- result.try(canvas.send(canvas:, req:))

  res
  |> json.parse(using: decode.list(user.decoder()))
  |> result.map_error(canvas.FailedToParseJson)
}
