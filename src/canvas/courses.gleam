import gleam/dynamic/decode
import gleam/http/request
import gleam/json
import gleam/option
import gleam/result

import canvas

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
  let req =
    req
    |> request.set_query([
      #("enrollment_type", case enrollment_type {
        Teacher -> "teacher"
        Student -> "student"
        TA -> "ta"
      }),
      #("enrollment_state", "active"),
    ])

  use res <- result.try(canvas.send(canvas:, req:))

  res
  |> json.parse(using: decode.list(decoder()))
  |> result.map_error(canvas.FailedToParseJson)
}
