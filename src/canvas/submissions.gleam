import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result

import canvas

pub type Submission {
  Submission(id: Int, user_id: Int, answers: List(Answer))
}

pub type Answer {
  Answer(question_id: Int, text: String)
}

fn decoder() -> decode.Decoder(Submission) {
  let decode_answer: decode.Decoder(Answer) = {
    use question_id <- decode.field("question_id", decode.int)
    use text <- decode.field("text", decode.string)

    decode.success(Answer(question_id:, text:))
  }

  use id <- decode.field("id", decode.int)
  use user_id <- decode.field("user_id", decode.int)
  use answers <- decode.field(
    "submission_history",
    decode.at(
      [0],
      decode.optional_field(
        "submission_data",
        [],
        decode.list(decode_answer),
        decode.success,
      ),
    ),
  )

  decode.success(Submission(id:, user_id:, answers:))
}

pub fn list_assignment_submissions(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  assignment_id assignment_id: Int,
) -> Result(List(Submission), canvas.Error) {
  let endpoint =
    "courses/"
    <> int.to_string(course_id)
    <> "/assignments/"
    <> int.to_string(assignment_id)
    <> "/submissions?include=submission_history"

  use req <- result.try(canvas.request(canvas:, endpoint:))

  use res <- result.try(canvas.send(canvas:, req:))

  res
  |> json.parse(using: decode.list(decoder()))
  |> result.map_error(canvas.FailedToParseJson)
}
