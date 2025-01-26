import gleam/bool
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/option
import gleam/result

import canvas/canvas
import canvas/form

pub type Quiz {
  Quiz(id: Int, assignment_id: Int)
}

pub type QuizParams {
  Create(
    title: option.Option(String),
    description: option.Option(String),
    quiz_type: option.Option(QuizType),
    assignment_group_id: option.Option(Int),
    published: option.Option(Bool),
  )
}

pub type QuizType {
  PracticeQuiz
  Assignment
  GradedSurvey
  Survey
}

fn encoder(params params: QuizParams) -> form.Form {
  let Create(title:, description:, quiz_type:, assignment_group_id:, published:) =
    params

  form.new()
  |> form.add("quiz[title]", form.optional(title, form.string))
  |> form.add("quiz[description]", form.optional(description, form.string))
  |> form.add(
    "quiz[quiz_type]",
    form.optional(from: quiz_type, of: {
      use quiz_type <- form.parameter

      case quiz_type {
        PracticeQuiz -> "practice_quiz"
        Assignment -> "assignment"
        GradedSurvey -> "graded_survey"
        Survey -> "survey"
      }
      |> form.string
    }),
  )
  |> form.add(
    "quiz[assignment_group_id]",
    form.optional(assignment_group_id, form.int),
  )
  |> form.add("quiz[published]", form.optional(published, form.bool))
  |> form.add("quiz[only_visible_to_overrides]", form.bool(True))
}

fn decoder() -> decode.Decoder(Quiz) {
  use id <- decode.field("id", decode.int)
  use assignment_id <- decode.field("assignment_id", decode.int)
  decode.success(Quiz(id:, assignment_id:))
}

pub fn create_new_quiz(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  params params: QuizParams,
) -> Result(Quiz, canvas.Error) {
  let endpoint = "courses/" <> int.to_string(course_id) <> "/quizzes"

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use resp <- result.try(
    req
    |> request.set_method(http.Post)
    |> request.set_body(encoder(params:) |> form.to_string)
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
