import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string

import gsv
import simplifile

import canvas
import canvas/question
import canvas/submissions

import cgq/fetch
import cgq/questions
import cgq/title

pub type Error {
  FailedToFetchSubmissions(fetch.Error)
  FailedToWriteToFile(simplifile.FileError)
}

type StudentData {
  StudentData(
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
  title_prefix title_prefix: String,
) {
  let distribute = template.distribute

  io.println("Fetching student peer evaluations...")

  use submissions <- result.try(
    fetch.fetch_submissions(canvas:, course_id:, quiz_title: title_prefix)
    |> result.map_error(FailedToFetchSubmissions),
  )

  let weekly_evaluations = {
    use #(week_title, week_submissions) <- list.map(submissions_by_week(
      submissions,
    ))

    let points = ratings_for_week(submissions: week_submissions, distribute:)

    use _, point <- dict.map_values(in: points)

    [#(week_title, float.to_string(point))]
  }

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

fn submissions_by_week(
  submissions submissions: List(fetch.QuizSubmission),
) -> List(#(String, List(fetch.QuizSubmission))) {
  {
    use weeks, submission <- list.fold(submissions, dict.new())
    let week = title.split(submission.quiz.title).base
    use existing <- dict.upsert(weeks, week)
    [submission, ..option.unwrap(existing, [])]
  }
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

pub fn ratings_for_week(
  submissions submissions: List(fetch.QuizSubmission),
  distribute distribute: questions.Distribute,
) -> dict.Dict(#(String, String), Float) {
  fetch_student_data(submissions:, distribute:)
  |> create_points_distribution
  |> normalize(points_per_member: distribute.points_per_member)
}

fn fetch_student_data(
  submissions submissions: List(fetch.QuizSubmission),
  distribute distribute: questions.Distribute,
) -> List(StudentData) {
  let #(prefix, suffix) = questions.member_name_affixes(distribute:)
  let prefix = string.lowercase(prefix)
  let suffix = string.lowercase(suffix)

  use submission <- list.flat_map(submissions)
  let fetch.QuizSubmission(user: _, quiz:, q_and_a:) = submission

  let group_name = title.split(quiz.title).group

  let members = {
    use #(question, answer) <- list.filter_map(q_and_a)
    use name <- result.map(member_name(question:, prefix:, suffix:))
    #(name, answer)
  }

  let member_count = list.length(members)
  let assigned_points =
    members
    |> list.filter_map(fn(member) {
      fetch_points_assigned_from_numeric_answer(answer: member.1)
    })
    |> int.sum

  let scale =
    result.unwrap(
      float.divide(int.to_float(member_count), int.to_float(assigned_points)),
      0.0,
    )

  use #(name, answer) <- list.map(members)
  StudentData(answer:, name:, group_name:, scale:)
}

fn member_name(
  question question: question.Question,
  prefix prefix: String,
  suffix suffix: String,
) -> Result(String, Nil) {
  use <- bool.guard(
    case question {
      question.Numerical(_, _) -> False
      _ -> True
    },
    Error(Nil),
  )

  let assert question.Numerical(text:, points: _) = question
  let lowered = string.lowercase(text)

  use <- bool.guard(!string.starts_with(lowered, prefix), Error(Nil))
  use <- bool.guard(!string.ends_with(lowered, suffix), Error(Nil))

  let name =
    text
    |> string.drop_start(string.length(prefix))
    |> string.drop_end(string.length(suffix))

  use <- bool.guard(string.is_empty(name), Error(Nil))

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
  use acc, StudentData(answer:, name:, group_name:, scale:) <- list.fold(
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
