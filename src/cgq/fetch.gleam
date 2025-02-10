import gleam/bool
import gleam/io
import gleam/list
import gleam/otp/task
import gleam/result
import gleam/string

import trellis
import trellis/column

import canvas
import canvas/question
import canvas/quiz
import canvas/submissions
import canvas/user

pub type Error {
  FailedToListQuizzes(canvas.Error)
  FailedToListSubmissions(canvas.Error)
  FailedToFetchUser(canvas.Error)
  FailedToFetchQuestions(canvas.Error)
  FailedAsync
  NotEssay
}

type QuizSubmissions {
  QuizSubmissions(
    user: user.User,
    quiz: quiz.Quiz,
    pairs: List(QuestionAnswerPair),
  )
}

type QuestionAnswerPair {
  QuestionAnswerPair(question: question.Question, answer: submissions.Answer)
}

pub fn fetch(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  quiz_title quiz_title: String,
) -> Result(Nil, Error) {
  use submissions <- result.map(submissions(canvas:, course_id:, quiz_title:))

  let submissions =
    list.filter(submissions, fn(submission) {
      let QuizSubmissions(user: _, quiz: _, pairs:) = submission

      use <- bool.guard(when: pairs == [], return: False)

      True
    })

  trellis.table(submissions)
  |> trellis.with(
    column.new(header: "Student Name")
    |> column.align(column.Left)
    |> column.render({
      use QuizSubmissions(user:, quiz: _, pairs: _) <- trellis.param
      let user.User(id: _, name:) = user
      name
    }),
  )
  |> trellis.with(
    column.new(header: "Quiz Title")
    |> column.align(column.Left)
    |> column.render({
      use QuizSubmissions(user: _, quiz:, pairs: _) <- trellis.param
      let quiz.Quiz(id: _, assignment_id: _, title:) = quiz
      title
    }),
  )
  |> trellis.with(
    column.new(header: "Complaint")
    |> column.align(column.Left)
    |> column.render({
      use QuizSubmissions(user: _, quiz: _, pairs:) <- trellis.param

      {
        use pair <- list.map(pairs)
        let QuestionAnswerPair(question: _, answer:) = pair
        let submissions.Answer(question_id: _, text:) = answer

        text |> sanitize
      }
      |> string.join("\n")
      |> string.append("\n")
    })
    |> column.wrap(80),
  )
  |> trellis.to_string
  |> io.println
}

fn submissions(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  quiz_title quiz_title: String,
) -> Result(List(QuizSubmissions), Error) {
  use quizzes <- result.try(
    quiz.list_quizzes(canvas:, course_id:, search_term: quiz_title)
    |> result.map_error(FailedToListQuizzes),
  )

  let quizzes_tasks = {
    use quiz <- list.map(quizzes)
    let quiz.Quiz(id: quiz_id, assignment_id:, title: _) = quiz

    task.async(fn() {
      use submissions <- result.map(
        submissions.list_assignment_submissions(
          canvas:,
          course_id:,
          assignment_id:,
        )
        |> result.map_error(FailedToListSubmissions),
      )

      use submission <- list.map(submissions)
      let submissions.Submission(id: _, user_id:, answers:) = submission
      let answers = answers |> list.filter(filter_answers)

      use user <- result.try(
        user.get_user(canvas:, course_id:, user_id:)
        |> result.map_error(FailedToFetchUser),
      )

      let pairs =
        {
          let pairs_tasks = {
            use answer <- list.map(answers)
            let submissions.Answer(question_id:, text: _) = answer

            task.async(fn() {
              question.get_single_question(
                canvas:,
                course_id:,
                quiz_id:,
                question_id:,
              )
              |> result.map(QuestionAnswerPair(question: _, answer:))
              |> result.map_error(FailedToFetchQuestions)
            })
          }

          use res <- list.map(task.try_await_all(pairs_tasks, 1_000_000))
          res
          |> result.replace_error(FailedAsync)
          |> result.flatten
        }
        |> result.all

      use pairs <- result.map(pairs)

      let pairs =
        pairs
        |> list.filter(fn(r) {
          case r.question {
            question.Essay(_, _) -> True
            _ -> False
          }
        })

      QuizSubmissions(user:, quiz:, pairs:)
    })
  }

  io.println("Fetching...")

  task.try_await_all(quizzes_tasks, 10_000_000)
  |> result.all
  |> result.map(result.all)
  |> result.replace_error(FailedAsync)
  |> result.flatten
  |> result.map(list.flatten)
  |> result.map(result.all)
  |> result.flatten
}

fn filter_answers(answer answer: submissions.Answer) -> Bool {
  let submissions.Answer(question_id: _, text:) = answer
  let text = text |> string.uppercase |> string.trim

  use <- bool.guard(when: text == "", return: False)

  let text =
    text
    |> string.drop_start(string.length("<P>"))
    |> string.drop_end(string.length("</P>"))
    |> string.trim

  text != "NA" && text != "N/A" && text != "NONE"
}

fn sanitize(text text: String) -> String {
  text
  |> string.drop_start(string.length("<p>"))
  |> string.drop_end(string.length("</p>"))
}
