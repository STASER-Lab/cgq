import gleam/bool
import gleam/dynamic/decode
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result

import canvas
import canvas/user

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

  use res <- result.try(canvas.send(req:))

  res
  |> json.parse(using: decode.list(decoder()))
  |> result.map_error(canvas.FailedToParseJson)
}

pub fn list_users(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  enrollment_type enrollment_type: EnrollmentType,
) -> Result(List(user.User), canvas.Error) {
  loop_list_users(canvas:, course_id:, enrollment_type:, page: 1, users: [])
}

fn loop_list_users(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  enrollment_type enrollment_type: EnrollmentType,
  page page: Int,
  users acc: List(user.User),
) -> Result(List(user.User), canvas.Error) {
  let endpoint = "courses/" <> int.to_string(course_id) <> "/users"

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
      #("sort", "username"),
      #("page", int.to_string(page)),
    ])

  use res <- result.try(canvas.send(req:))

  let res =
    res
    |> json.parse(using: decode.list(user.decoder()))
    |> result.map_error(canvas.FailedToParseJson)

  use users <- result.try(res)

  use <- bool.guard(users |> list.is_empty, acc |> Ok)

  let users = list.append(acc, users)
  loop_list_users(canvas:, course_id:, enrollment_type:, page: page + 1, users:)
}
