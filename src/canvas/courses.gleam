import gleam/bool
import gleam/dynamic/decode
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/option
import gleam/result

import canvas/canvas

pub type Course {
  Course(id: Int, name: option.Option(String))
}

pub type EnrollmentType {
  Teacher
  Student
  TA
}

fn decoder() -> decode.Decoder(Course) {
  use id <- decode.field("id", decode.int)
  use name <- decode.optional_field(
    "name",
    option.None,
    decode.optional(decode.string),
  )
  decode.success(Course(id:, name:))
}

pub fn list_courses(
  canvas canvas: canvas.Canvas,
  enrollment_type enrollment_type: EnrollmentType,
) -> Result(List(Course), canvas.Error) {
  let endpoint = "courses"

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use res <- result.try(
    req
    |> request.set_query([
      #("enrollment_type", case enrollment_type {
        Teacher -> "teacher"
        Student -> "student"
        TA -> "ta"
      }),
      #("enrollment_state", "active"),
    ])
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
