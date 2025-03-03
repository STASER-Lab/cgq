import gleam/bool
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/uri

import canvas
import canvas/form

pub type Quiz {
  Quiz(id: Int, assignment_id: Int, title: String)
}

pub type QuizParams {
  Create(
    title: option.Option(String),
    description: option.Option(String),
    quiz_type: option.Option(QuizType),
    assignment_group_id: option.Option(Int),
    points_possible: option.Option(Int),
  )
}

pub type QuizType {
  PracticeQuiz
  Assignment
  GradedSurvey
  Survey
}

fn encoder(params params: QuizParams) -> form.Form {
  let Create(
    title:,
    description:,
    quiz_type:,
    assignment_group_id:,
    points_possible:,
  ) = params

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
  |> form.add("quiz[points_possible]", form.optional(points_possible, form.int))
}

fn decoder() -> decode.Decoder(Quiz) {
  use id <- decode.field("id", decode.int)
  use assignment_id <- decode.field("assignment_id", decode.int)
  use title <- decode.field("title", decode.string)
  decode.success(Quiz(id:, assignment_id:, title:))
}

pub fn create_new_quiz(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  params params: QuizParams,
) -> Result(Quiz, canvas.Error) {
  let endpoint = "courses/" <> int.to_string(course_id) <> "/quizzes"

  use req <- result.try(canvas.request(canvas:, endpoint:))
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_body(
      encoder(params:)
      |> form.add("quiz[published]", form.bool(False))
      |> form.add("quiz[only_visible_to_overrides]", form.bool(True))
      |> form.to_string,
    )

  use res <- result.try(canvas.send(canvas:, req:))

  res
  |> json.parse(using: decoder())
  |> result.map_error(canvas.FailedToParseJson)
}

pub fn publish_quiz(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  quiz_id quiz_id: Int,
) -> Result(Nil, canvas.Error) {
  let endpoint =
    "courses/"
    <> int.to_string(course_id)
    <> "/quizzes/"
    <> int.to_string(quiz_id)

  use req <- result.try(canvas.request(canvas:, endpoint:))
  let req =
    req
    |> request.set_method(http.Put)
    |> request.set_body(
      form.new()
      |> form.add("quiz[published]", form.bool(True))
      |> form.to_string,
    )

  canvas.send(canvas:, req:) |> result.replace(Nil)
}

pub fn list_quizzes(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  search_term search_term: String,
) -> Result(List(Quiz), canvas.Error) {
  loop_list_quizzes(canvas:, course_id:, search_term:, page: 1, quizzes: [])
}

fn loop_list_quizzes(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  search_term search_term: String,
  page page: Int,
  quizzes acc: List(Quiz),
) {
  let query = [#("page", int.to_string(page))]

  let query =
    {
      use <- bool.guard(search_term == "", query)
      [#("search_term", search_term), ..query]
    }
    |> uri.query_to_string

  let endpoint = "courses/" <> int.to_string(course_id) <> "/quizzes"

  let endpoint =
    [endpoint, query]
    |> list.filter(fn(str) { str != "" })
    |> string.join("?")
    |> string.replace(each: " ", with: "%20")

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use res <- result.try(canvas.send(canvas:, req:))

  let res =
    res
    |> json.parse(using: decode.list(decoder()))
    |> result.map_error(canvas.FailedToParseJson)

  use quizzes <- result.try(res)

  use <- bool.guard(quizzes |> list.is_empty, acc |> Ok)

  loop_list_quizzes(
    canvas:,
    course_id:,
    search_term:,
    page: page + 1,
    quizzes: list.append(acc, quizzes),
  )
}
