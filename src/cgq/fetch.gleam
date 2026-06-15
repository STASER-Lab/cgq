import canvas/courses
import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/task
import gleam/result
import gleam/string

import gsv
import simplifile
import trellis
import trellis/column

import canvas
import canvas/question
import canvas/quiz
import canvas/submissions
import canvas/user

pub type Error {
  FailedToListStudents(canvas.Error)
  FailedToListQuizzes(canvas.Error)
  FailedToListSubmissions(canvas.Error)
  FailedToFetchQuestions(canvas.Error)
  FailedAsync
  FailedToWriteToFile(simplifile.FileError)
}

pub fn error_message(error error: Error) -> String {
  case error {
    FailedToListStudents(error) ->
      "could not list students: " <> canvas.error_message(error)
    FailedToListQuizzes(error) ->
      "could not list quizzes: " <> canvas.error_message(error)
    FailedToListSubmissions(error) ->
      "could not list submissions: " <> canvas.error_message(error)
    FailedToFetchQuestions(error) ->
      "could not load quiz questions: " <> canvas.error_message(error)
    FailedAsync -> "a fetch task did not finish"
    FailedToWriteToFile(error) ->
      "could not write the output file: " <> simplifile.describe_error(error)
  }
}

const await_timeout_microseconds = 60_000_000

pub type QuizSubmission {
  QuizSubmission(
    user: user.User,
    quiz: quiz.Quiz,
    q_and_a: List(#(question.Question, submissions.Answer)),
  )
}

pub fn fetch(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  quiz_title quiz_title: String,
) -> Result(Nil, Error) {
  use submissions <- result.map(fetch_submissions(
    canvas:,
    course_id:,
    quiz_title:,
  ))

  let submissions =
    submissions
    |> list.filter_map(fn(submission) {
      let QuizSubmission(user: _, quiz: _, q_and_a:) = submission

      let q_and_a = {
        use #(question, answer) <- list.filter(q_and_a)
        filter_answers(answer) && filter_question(question)
      }

      use <- bool.guard(list.is_empty(q_and_a), Error(Nil))

      QuizSubmission(..submission, q_and_a:) |> Ok
    })

  trellis.table(submissions)
  |> trellis.with(
    column.new(header: "Student Name")
    |> column.align(column.Left)
    |> column.render({
      use QuizSubmission(user:, quiz: _, q_and_a: _) <- trellis.param
      let user.User(id: _, name:) = user
      name
    }),
  )
  |> trellis.with(
    column.new(header: "Quiz Title")
    |> column.align(column.Left)
    |> column.render({
      use QuizSubmission(user: _, quiz:, q_and_a: _) <- trellis.param
      let quiz.Quiz(id: _, assignment_id: _, title:) = quiz
      title
    }),
  )
  |> trellis.with(
    column.new(header: "Complaint")
    |> column.align(column.Left)
    |> column.render({
      use QuizSubmission(user: _, quiz: _, q_and_a:) <- trellis.param

      {
        use #(_, answer) <- list.map(q_and_a)
        let submissions.Answer(question_id: _, text:) = answer

        text |> sanitize
      }
      |> string.join("\n")
      |> string.append("\n")
    })
    |> column.wrap(40),
  )
  |> trellis.to_string
  |> io.println
}

fn filter_question(question question: question.Question) -> Bool {
  case question {
    question.Essay(_, _) -> True
    _ -> False
  }
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

  text != "NA" && text != "N/A" && text != "NONE" && text != "NO COMMENTS."
}

fn sanitize(text text: String) -> String {
  text
  |> string.drop_start(string.length("<p>"))
  |> string.drop_end(string.length("</p>"))
}

pub fn fetch_submissions(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  quiz_title quiz_title: String,
) -> Result(List(QuizSubmission), Error) {
  io.println("Fetching quizzes for " <> quiz_title <> "...")

  use quizzes <- result.try(
    quiz.list_quizzes(canvas:, course_id:, search_term: quiz_title)
    |> result.map_error(FailedToListQuizzes),
  )

  let quizzes_tasks = {
    use quiz <- list.map(quizzes)
    let quiz.Quiz(id: quiz_id, assignment_id:, title: _) = quiz

    use <- task.async

    use questions <- result.try(
      question.list_questions(canvas:, course_id:, quiz_id:)
      |> result.map_error(FailedToFetchQuestions),
    )
    let question_by_id = dict.from_list(questions)

    use submissions <- result.map(
      submissions.list_assignment_submissions(
        canvas:,
        course_id:,
        assignment_id:,
      )
      |> result.map_error(FailedToListSubmissions),
    )

    use submissions.Submission(id: _, user:, answers:) <- list.map(submissions)

    let q_and_a = {
      use answer <- list.filter_map(answers)
      let submissions.Answer(question_id:, text: _) = answer
      use question <- result.map(dict.get(question_by_id, question_id))
      #(question, answer)
    }

    QuizSubmission(user:, quiz:, q_and_a:)
  }

  io.println("Fetching quiz submissions for " <> quiz_title <> "...")

  use <- defer(fn() {
    io.println("Fetched submissions for " <> quiz_title <> ".")
  })

  task.try_await_all(quizzes_tasks, await_timeout_microseconds)
  |> result.all
  |> result.replace_error(FailedAsync)
  |> result.map(result.all)
  |> result.flatten
  |> result.map(list.flatten)
  |> result.map(
    list.filter(_, fn(submission) {
      let QuizSubmission(user: _, quiz: _, q_and_a:) = submission

      list.is_empty(q_and_a) |> bool.negate
    }),
  )
}

pub fn percent_completed(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  filepath filepath: String,
  title_prefix title_prefix: String,
) {
  use students <- result.try(
    courses.list_users(canvas:, course_id:, enrollment_type: courses.Student)
    |> result.map_error(FailedToListStudents),
  )

  let map = {
    use map, student <- list.fold(students, dict.new())

    dict.insert(map, student, [])
  }

  use quizzes <- result.try(
    quiz.list_quizzes(canvas:, course_id:, search_term: title_prefix)
    |> result.map_error(FailedToListQuizzes),
  )

  let total_quizzes = list.length(quizzes)

  let tasks = {
    use quiz <- list.map(quizzes)
    let quiz.Quiz(id: _, assignment_id:, title: _) = quiz

    use <- task.async

    use submissions <- result.map(
      submissions.list_assignment_submissions(
        canvas:,
        course_id:,
        assignment_id:,
      )
      |> result.map_error(FailedToListSubmissions),
    )

    use submissions.Submission(id:, user:, answers:) <- list.map(submissions)

    use <- bool.guard(answers |> list.is_empty, option.None)

    #(user, [id]) |> option.Some
  }

  let users =
    task.try_await_all(tasks, await_timeout_microseconds)
    |> result.all
    |> result.replace_error(FailedAsync)
    |> result.map(result.all)
    |> result.flatten
    |> result.map(list.flatten)
    |> result.map(option.values)

  use users <- result.try(users)

  let map = {
    use map, #(user, submissions) <- list.fold(users, map)

    use count <- dict.upsert(map, user)
    let count = option.unwrap(count, [])

    list.append(submissions, count)
  }

  {
    use rows, user, submissions <- dict.fold(map, [])

    let submissions = list.unique(submissions)

    let count = list.length(submissions)

    let percent = case total_quizzes {
      0 -> 0.0
      _ ->
        int.to_float(count) /. int.to_float(total_quizzes)
        |> float.to_precision(4)
    }

    dict.new()
    |> dict.insert("Name", user.name)
    |> dict.insert("Student ID", user.id |> int.to_string)
    |> dict.insert("Quizzes Completed", count |> int.to_string)
    |> dict.insert("Percent Completed", percent |> float.to_string)
    |> list.prepend(rows, _)
  }
  |> gsv.from_dicts(",", gsv.Unix)
  |> simplifile.write(to: filepath)
  |> result.map_error(FailedToWriteToFile)
}

fn defer(defer: fn() -> b, continue: fn() -> a) -> a {
  let retval = continue()
  defer()
  retval
}
