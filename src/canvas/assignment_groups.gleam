import gleam/bool
import gleam/dynamic/decode
import gleam/httpc
import gleam/int
import gleam/json
import gleam/result

import canvas/canvas

pub type AssignmentGroup {
  AssignmentGroup(id: Int, name: String)
}

fn decoder() -> decode.Decoder(AssignmentGroup) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  decode.success(AssignmentGroup(id:, name:))
}

pub fn list_assignment_groups(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
) -> Result(List(AssignmentGroup), canvas.Error) {
  let endpoint = "courses/" <> int.to_string(course_id) <> "/assignment_groups"

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
