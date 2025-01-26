import gleam/bool
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/option
import gleam/result

import birl

import canvas/canvas
import canvas/form

pub type AssignmentOverride {
  AssignmentOverride(
    assignment_id: Int,
    quiz_id: Int,
    student_ids: List(Int),
    due_at: option.Option(birl.Time),
    unlock_at: option.Option(birl.Time),
  )
}

fn encoder(
  assignment_override assignment_override: AssignmentOverride,
) -> form.Form {
  let AssignmentOverride(
    assignment_id: _,
    quiz_id: _,
    student_ids:,
    due_at:,
    unlock_at:,
  ) = assignment_override

  form.new()
  |> form.add(
    "assignment_override[student_ids][]",
    form.list(student_ids, form.int),
  )
  |> form.add("assignment_override[due_at]", form.optional(due_at, form.time))
  |> form.add(
    "assignment_override[unlock_at]",
    form.optional(unlock_at, form.time),
  )
}

fn decoder() -> decode.Decoder(AssignmentOverride) {
  use assignment_id <- decode.field("assignment_id", decode.int)
  use quiz_id <- decode.field("quiz_id", decode.int)
  use student_ids <- decode.field("student_ids", decode.list(decode.int))
  use due_at <- decode.optional_field(
    "due_at",
    option.None,
    decode.map(decode.string, fn(x) { x |> birl.parse |> option.from_result }),
  )
  use unlock_at <- decode.optional_field(
    "unlock_at",
    option.None,
    decode.map(decode.string, fn(x) { x |> birl.parse |> option.from_result }),
  )
  decode.success(AssignmentOverride(
    assignment_id:,
    quiz_id:,
    student_ids:,
    due_at:,
    unlock_at:,
  ))
}

pub fn create_assignment_override(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  assignment_override assignment_override: AssignmentOverride,
) -> Result(AssignmentOverride, canvas.Error) {
  let endpoint =
    "courses/"
    <> int.to_string(course_id)
    <> "/assignments/"
    <> int.to_string(assignment_override.assignment_id)
    <> "/overrides"

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use res <- result.try(
    req
    |> request.set_method(http.Post)
    |> request.set_body(assignment_override |> encoder |> form.to_string)
    |> httpc.send
    |> result.map_error(canvas.FailedToSendRequest),
  )

  use <- bool.guard(
    res.status != 201,
    res.status |> canvas.FailedRequestStatus |> Error,
  )

  res.body
  |> json.parse(using: decoder())
  |> result.map_error(canvas.FailedToParseJson)
}
