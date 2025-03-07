import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/io
import gleam/list
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
  FailedToListQuizzes(canvas.Error)
  FailedToListSubmissions(canvas.Error)
  FailedToFetchUser(canvas.Error)
  FailedToFetchQuestions(canvas.Error)
  FailedAsync
  FailedToWriteToFile(simplifile.FileError)
  FailedToFetchStudentData
  FailedToCreatePointDistribution

  FailedToDivide
  FailedToFetchGroupPoints
  FailedToFetchStudentName

  QuestionIsNotNumeric
}

type QuizSubmission {
  QuizSubmission(
    user: user.User,
    quiz: quiz.Quiz,
    q_and_a: List(#(question.Question, submissions.Answer)),
  )
}

type StudentData {
  StudentData(
    question: question.Question,
    answer: submissions.Answer,
    name: String,
    group_name: String,
    scale: Float,
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

      use <- bool.guard(list.is_empty(q_and_a), Error(Nil))

      let q_and_a = {
        use #(_, answer) <- list.filter(q_and_a)
        filter_answers(answer)
      }

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

pub fn fetch_student_ratings(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  filepath filepath: String,
) {
  let weeks = list.range(from: 3, to: 7)

  let tasks = {
    use week <- list.map(weeks)

    use <- task.async

    let quiz_title = "Week " <> int.to_string(week)

    use submissions <- result.try(fetch_submissions(
      canvas:,
      course_id:,
      quiz_title:,
    ))

    use student_data <- result.try(fetch_student_data(submissions:))

    use points <- result.map(
      create_points_distribution(student_data:)
      |> result.replace_error(FailedToCreatePointDistribution),
    )

    use _, point <- dict.map_values(in: points)

    let point = point |> float.to_string

    [#(quiz_title, point)]
  }

  io.println("Fetching student peer evaluations...")

  let weekly_evaluations =
    task.try_await_all(tasks, 1_000_000)
    |> result.all
    |> result.replace_error(FailedAsync)
    |> result.map(result.all)
    |> result.flatten

  use weekly_evaluations <- result.try(weekly_evaluations)

  let weekly_evaluations = {
    use one, other <- list.fold(weekly_evaluations, dict.new())

    dict.combine(one, other, list.append)
  }

  {
    use #(group_name, name), row <- dict.map_values(weekly_evaluations)

    row
    |> list.prepend(#("Group Name", group_name))
    |> list.prepend(#("Name", name))
    |> dict.from_list
  }
  |> dict.values
  |> list.sort(fn(a, b) {
    let assert Ok(group_name_a) = dict.get(a, "Group Name")
    let assert Ok(group_name_b) = dict.get(b, "Group Name")

    string.compare(group_name_a, group_name_b)
  })
  |> gsv.from_dicts(",", gsv.Unix)
  |> simplifile.write(to: filepath)
  |> result.map_error(FailedToWriteToFile)
}

fn fetch_submissions(
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

    use submissions <- result.map(
      submissions.list_assignment_submissions(
        canvas:,
        course_id:,
        assignment_id:,
      )
      |> result.map_error(FailedToListSubmissions),
    )

    use submissions.Submission(id: _, user_id:, answers:) <- list.map(
      submissions,
    )

    use user <- result.try(
      user.get_user(canvas:, course_id:, user_id:)
      |> result.map_error(FailedToFetchUser),
    )

    use questions <- result.map(fetch_questions(
      canvas:,
      course_id:,
      quiz_id:,
      answers:,
    ))

    let q_and_a = list.zip(questions, answers)

    QuizSubmission(user:, quiz:, q_and_a:)
  }

  io.println("Fetching quiz submissions for " <> quiz_title <> "...")

  use <- defer(fn() {
    io.println("Fetched submissions for " <> quiz_title <> ".")
  })

  task.try_await_all(quizzes_tasks, 10_000_000)
  |> result.all
  |> result.map(result.all)
  |> result.replace_error(FailedAsync)
  |> result.flatten
  |> result.map(list.flatten)
  |> result.map(result.all)
  |> result.flatten
  |> result.map(
    list.filter(_, fn(submission) {
      let QuizSubmission(user: _, quiz: _, q_and_a:) = submission

      list.is_empty(q_and_a) |> bool.negate
    }),
  )
}

fn fetch_questions(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  quiz_id quiz_id: Int,
  answers answers: List(submissions.Answer),
) -> Result(List(question.Question), Error) {
  let tasks = {
    use submissions.Answer(question_id:, text: _) <- list.map(answers)

    use <- task.async

    question.get_single_question(canvas:, course_id:, quiz_id:, question_id:)
    |> result.map_error(FailedToFetchQuestions)
  }

  task.try_await_all(tasks, 1_000_000)
  |> result.all
  |> result.replace_error(FailedAsync)
  |> result.map(result.all)
  |> result.flatten
}

fn fetch_group_points(submission submission: QuizSubmission) -> Result(Int, Nil) {
  let QuizSubmission(user: _, quiz: _, q_and_a:) = submission

  use #(question, _) <- list.find_map(q_and_a)

  let prefix = "Based on this week, you need to distribute " |> string.lowercase

  use <- bool.guard(
    case question {
      question.Text(_) -> False
      _ -> True
    },
    Error(Nil),
  )

  let assert question.Text(text:) = question

  use <- bool.guard(
    text |> string.lowercase |> string.starts_with(prefix) |> bool.negate,
    Error(Nil),
  )

  let text =
    text
    |> string.drop_start(string.length(prefix))
    |> string.split_once(" ")

  use #(points, _) <- result.try(text)

  int.parse(points)
}

fn fetch_assigned_points(submission submission: QuizSubmission) -> Int {
  let QuizSubmission(user: _, quiz: _, q_and_a:) = submission

  {
    use #(question, answer) <- list.filter_map(q_and_a)

    use <- bool.guard(
      case question {
        question.Numerical(_, _) -> False
        _ -> True
      },
      Error(Nil),
    )

    let assert question.Numerical(text:, points: _) = question

    let prefix = "The points distributed for " |> string.lowercase

    use <- bool.guard(
      text |> string.lowercase |> string.starts_with(prefix) |> bool.negate,
      Error(Nil),
    )

    fetch_points_assigned_from_numeric_answer(answer:)
  }
  |> int.sum
}

fn fetch_student_name_from_question(
  question question: question.Question,
) -> Result(String, Error) {
  use <- bool.guard(
    case question {
      question.Numerical(_, _) -> False
      _ -> True
    },
    Error(FailedToFetchStudentName),
  )

  let assert question.Numerical(text:, points: _) = question

  let prefix = "The points distributed for " |> string.lowercase

  use <- bool.guard(
    text |> string.lowercase |> string.starts_with(prefix) |> bool.negate,
    Error(FailedToFetchStudentName),
  )

  let name =
    text
    |> string.drop_start(string.length(prefix))

  use <- bool.guard(string.is_empty(name), Error(FailedToFetchStudentName))

  name |> Ok
}

fn fetch_student_data(
  submissions submissions: List(QuizSubmission),
) -> Result(List(StudentData), Error) {
  use <- bool.guard(list.is_empty(submissions), [] |> Ok)

  use acc, submission <- list.fold(submissions, [] |> Ok)
  use acc <- result.try(acc)
  let QuizSubmission(user: _, quiz:, q_and_a:) = submission

  let group_name = quiz.title |> string.drop_start(string.length("Week 4: "))

  use group_points <- result.try(
    fetch_group_points(submission:)
    |> result.replace_error(FailedToFetchGroupPoints),
  )
  let assigned_points = fetch_assigned_points(submission)

  use scale <- result.map(
    float.divide(int.to_float(group_points), int.to_float(assigned_points))
    |> result.replace_error(FailedToDivide),
  )

  let student_data = {
    use #(question, answer) <- list.filter_map(q_and_a)

    use name <- result.map(fetch_student_name_from_question(question:))

    StudentData(question:, answer:, name:, group_name:, scale:)
  }

  list.append(acc, student_data)
}

fn fetch_points_assigned_from_numeric_answer(
  answer answer: submissions.Answer,
) -> Result(Int, Nil) {
  let submissions.Answer(question_id: _, text:) = answer

  let text = text |> string.trim

  result.or(int.parse(text), float.parse(text) |> result.map(float.round))
}

fn create_points_distribution(
  student_data student_data: List(StudentData),
) -> Result(dict.Dict(#(String, String), Float), Nil) {
  {
    use StudentData(question: _, answer:, name:, group_name:, scale:) <- list.map(
      student_data,
    )

    let key = #(group_name, name)

    let submissions.Answer(question_id: _, text:) = answer

    let text = text |> string.trim

    use point: Float <- result.map(result.or(
      int.parse(text) |> result.map(int.to_float),
      float.parse(text),
    ))

    let value = point *. scale

    #(key, value)
  }
  |> result.all
  |> result.map(dict.from_list)
}

fn defer(defer: fn() -> b, continue: fn() -> a) -> a {
  let retval = continue()
  defer()
  retval
}
