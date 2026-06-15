import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result

import canvas

pub type GroupCategory {
  GroupCategory(id: Int, name: String)
}

fn decoder() -> decode.Decoder(GroupCategory) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  decode.success(GroupCategory(id:, name:))
}

pub fn list_group_categories(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
) -> Result(List(GroupCategory), canvas.Error) {
  loop_list_group_categories(canvas:, course_id:, page: 1, categories: [])
}

fn loop_list_group_categories(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  page page: Int,
  categories acc: List(GroupCategory),
) -> Result(List(GroupCategory), canvas.Error) {
  let endpoint =
    "courses/"
    <> int.to_string(course_id)
    <> "/group_categories?page="
    <> int.to_string(page)

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use res <- result.try(canvas.send(req:))

  use categories <- result.try(
    res
    |> json.parse(using: decode.list(decoder()))
    |> result.map_error(canvas.FailedToParseJson),
  )

  use <- bool.guard(categories |> list.is_empty, acc |> Ok)

  let categories = list.append(acc, categories)
  loop_list_group_categories(canvas:, course_id:, page: page + 1, categories:)
}
