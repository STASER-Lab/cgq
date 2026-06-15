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

import canvas
import canvas/question
import canvas/submissions

import cgq/fetch
import cgq/questions

pub type Error {
  FailedToFetchSubmissions(fetch.Error)
  FailedToFetchGroupPoints
  FailedToFetchStudentName
  FailedAsync
  FailedToWriteToFile(simplifile.FileError)
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

pub fn create_question(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  quiz_id quiz_id: Int,
  template template: questions.Template,
  student_names student_names: List(String),
) -> Result(Nil, canvas.Error) {
  let question_list = questions.to_questions(template:, student_names:)

  use _, question <- list.try_fold(question_list, Nil)
  question.create_new_question(canvas:, course_id:, quiz_id:, question:)
}

pub fn fetch_student_ratings(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  filepath filepath: String,
  template template: questions.Template,
) {
  let weeks = list.range(from: 9, to: 14)

  let distribute = template.distribute

  let tasks = {
    use week <- list.map(weeks)

    use <- task.async

    let quiz_title = "Week " <> int.to_string(week)

    use submissions <- result.try(
      fetch.fetch_submissions(canvas:, course_id:, quiz_title:)
      |> result.map_error(FailedToFetchSubmissions),
    )

    use points <- result.map(ratings_for_week(submissions:, distribute:))

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

    let assert Ok(name_a) = dict.get(a, "Name")
    let assert Ok(name_b) = dict.get(b, "Name")

    let a = group_name_a <> name_a
    let b = group_name_b <> name_b

    string.compare(a, b)
  })
  |> gsv.from_dicts(",", gsv.Unix)
  |> simplifile.write(to: filepath)
  |> result.map_error(FailedToWriteToFile)
}

pub fn ratings_for_week(
  submissions submissions: List(fetch.QuizSubmission),
  distribute distribute: questions.Distribute,
) -> Result(dict.Dict(#(String, String), Float), Error) {
  use student_data <- result.map(fetch_student_data(submissions:, distribute:))

  student_data
  |> create_points_distribution
  |> normalize(points_per_member: distribute.points_per_member)
}

fn fetch_student_data(
  submissions submissions: List(fetch.QuizSubmission),
  distribute distribute: questions.Distribute,
) -> Result(List(StudentData), Error) {
  use <- bool.guard(list.is_empty(submissions), [] |> Ok)

  let group_points_prefix =
    questions.group_points_match_prefix(distribute:) |> string.lowercase
  let member_name_prefix =
    questions.member_name_match_prefix(distribute:) |> string.lowercase
  let points_per_member = int.to_float(distribute.points_per_member)

  use acc, submission <- list.fold(submissions, [] |> Ok)
  use acc <- result.try(acc)
  let fetch.QuizSubmission(user: _, quiz:, q_and_a:) = submission

  let group_name =
    quiz.title
    |> string.split_once(": ")
    |> result.map(fn(parts) { parts.1 })
    |> result.unwrap(quiz.title)

  use group_points <- result.map(
    fetch_group_points(submission:, prefix: group_points_prefix)
    |> result.replace_error(FailedToFetchGroupPoints),
  )
  let group_points = int.to_float(group_points)
  let group_points =
    result.unwrap(float.divide(group_points, points_per_member), 0.0)

  let assigned_points =
    fetch_assigned_points(submission:, prefix: member_name_prefix)
    |> int.to_float

  let scale = result.unwrap(float.divide(group_points, assigned_points), 0.0)

  let student_data = {
    use #(question, answer) <- list.filter_map(q_and_a)

    use name <- result.map(fetch_student_name_from_question(
      question:,
      prefix: member_name_prefix,
    ))

    StudentData(question:, answer:, name:, group_name:, scale:)
  }

  list.append(acc, student_data)
}

fn fetch_group_points(
  submission submission: fetch.QuizSubmission,
  prefix prefix: String,
) -> Result(Int, Nil) {
  let fetch.QuizSubmission(user: _, quiz: _, q_and_a:) = submission

  use #(question, _) <- list.find_map(q_and_a)

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

fn fetch_assigned_points(
  submission submission: fetch.QuizSubmission,
  prefix prefix: String,
) -> Int {
  let fetch.QuizSubmission(user: _, quiz: _, q_and_a:) = submission

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
  prefix prefix: String,
) -> Result(String, Error) {
  use <- bool.guard(
    case question {
      question.Numerical(_, _) -> False
      _ -> True
    },
    Error(FailedToFetchStudentName),
  )

  let assert question.Numerical(text:, points: _) = question

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

fn fetch_points_assigned_from_numeric_answer(
  answer answer: submissions.Answer,
) -> Result(Int, Nil) {
  let submissions.Answer(question_id: _, text:) = answer

  let text = text |> string.trim

  result.or(int.parse(text), float.parse(text) |> result.map(float.round))
}

fn create_points_distribution(
  student_data student_data: List(StudentData),
) -> dict.Dict(#(String, String), Float) {
  use acc, StudentData(question: _, answer:, name:, group_name:, scale:) <- list.fold(
    student_data,
    dict.new(),
  )

  let key = #(group_name, name)

  let submissions.Answer(question_id: _, text:) = answer

  let text = text |> string.trim

  let point =
    result.unwrap(
      result.or(int.parse(text) |> result.map(int.to_float), float.parse(text)),
      0.0,
    )

  let value = point *. scale

  use point <- dict.upsert(acc, key)

  let point = option.unwrap(point, 0.0)

  point +. value
}

fn normalize(
  points points: dict.Dict(#(String, String), Float),
  points_per_member points_per_member: Int,
) {
  let normalizing_constants = {
    use acc, #(group_name, _), point <- dict.fold(points, dict.new())

    use constants <- dict.upsert(acc, group_name)

    let #(sum, count) = option.unwrap(constants, #(0.0, 0))
    let sum = sum +. point

    #(sum, count + 1)
  }

  use #(group_name, _), value <- dict.map_values(points)

  let assert Ok(#(sum, count)) = dict.get(normalizing_constants, group_name)

  int.to_float(points_per_member) *. int.to_float(count) *. value /. sum
}
