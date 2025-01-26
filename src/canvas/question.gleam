import gleam/bool
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/option
import gleam/result

import canvas/canvas
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

  use resp <- result.try(
    req
    |> request.set_method(http.Post)
    |> request.set_body(question |> encoder() |> form.to_string)
    |> httpc.send
    |> result.map_error(canvas.FailedToSendRequest),
  )

  use <- bool.guard(
    resp.status != 200,
    resp.status |> canvas.FailedRequestStatus |> Error,
  )

  Ok(Nil)
}
