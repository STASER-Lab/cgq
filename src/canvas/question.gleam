import gleam/dynamic/decode
import gleam/float
import gleam/http
import gleam/http/request
import gleam/int
import gleam/json
import gleam/option
import gleam/result

import canvas
import canvas/form

pub type Question {
  MultipleChoice(
    text: String,
    points: option.Option(Int),
    answers: List(Answer),
  )
  Numerical(text: String, points: option.Option(Int))
  Text(text: String)
  Essay(text: String, points: option.Option(Int))
}

pub type Answer {
  Answer(text: String, weight: Weight)
}

pub type Weight {
  Correct
  Incorrect
}

fn decoder() -> decode.Decoder(Question) {
  use question_type <- decode.field("question_type", decode.string)
  use text <- decode.field("question_text", decode.string)
  use points <- decode.optional_field(
    "points_possible",
    option.None,
    decode.optional(
      decode.one_of(decode.int, [decode.map(decode.float, float.round)]),
    ),
  )
  use answers <- decode.optional_field(
    "answers",
    [],
    decode.list({
      use text <- decode.field("answer_text", decode.string)
      use weight <- decode.field("answer_weight", decode.int)
      let weight = case weight {
        100 -> Correct |> decode.success
        0 -> Incorrect |> decode.success
        _ -> decode.failure(Incorrect, "Expected Weight")
      }
      use weight <- decode.then(weight)
      decode.success(Answer(text:, weight:))
    }),
  )

  case question_type {
    "multiple_choice_question" ->
      decode.success(MultipleChoice(text:, points:, answers:))
    "numerical_question" -> decode.success(Numerical(text:, points:))
    "text_only_question" -> decode.success(Text(text:))
    "essay_question" -> decode.success(Essay(text:, points:))
    _ ->
      decode.failure(
        MultipleChoice("", option.None, []),
        "incorrect question_type",
      )
  }
}

fn encoder(question: Question) -> form.Form {
  case question {
    MultipleChoice(text:, points:, answers:) ->
      form.new()
      |> form.add("question[question_text]", form.string(text))
      |> form.add(
        "question[question_type]",
        form.string("multiple_choice_question"),
      )
      |> form.add("question[points_possible]", form.optional(points, form.int))
      |> form.add(
        "question[answers][]",
        form.list(
          answers,
          form.object(_, {
            use answer: Answer <- form.parameter
            [
              #("answer_text", form.string(answer.text)),
              #(
                "answer_weight",
                form.int(case answer.weight {
                  Correct -> 100
                  Incorrect -> 0
                }),
              ),
            ]
          }),
        ),
      )
    Numerical(text:, points:) ->
      form.new()
      |> form.add("question[question_text]", form.string(text))
      |> form.add("question[question_type]", form.string("numerical_question"))
      |> form.add("question[points_possible]", form.optional(points, form.int))
    Text(text:) ->
      form.new()
      |> form.add("question[question_text]", form.string(text))
      |> form.add("question[question_type]", form.string("text_only_question"))
    Essay(text:, points:) ->
      form.new()
      |> form.add("question[question_text]", form.string(text))
      |> form.add("question[question_type]", form.string("essay_question"))
      |> form.add("question[points_possible]", form.optional(points, form.int))
  }
}

pub fn create_new_question(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  quiz_id quiz_id: Int,
  question question: Question,
) -> Result(Nil, canvas.Error) {
  let endpoint =
    "courses/"
    <> int.to_string(course_id)
    <> "/quizzes/"
    <> int.to_string(quiz_id)
    <> "/questions"

  use req <- result.try(canvas.request(canvas:, endpoint:))
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_body(question |> encoder() |> form.to_string)

  use _ <- result.map(canvas.send(canvas:, req:))

  Nil
}

pub fn get_single_question(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  quiz_id quiz_id: Int,
  question_id question_id: Int,
) -> Result(Question, canvas.Error) {
  let endpoint =
    "courses/"
    <> int.to_string(course_id)
    <> "/quizzes/"
    <> int.to_string(quiz_id)
    <> "/questions/"
    <> int.to_string(question_id)

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use res <- result.try(canvas.send(canvas:, req:))

  res
  |> json.parse(using: decoder())
  |> result.map_error(canvas.FailedToParseJson)
}
