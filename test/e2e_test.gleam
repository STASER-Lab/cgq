import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string

import gleeunit/should
import gsv
import simplifile

import canvas
import canvas/quiz
import cgq/create
import cgq/eval
import cgq/fetch
import cgq/questions

@external(erlang, "mock_canvas", "start")
fn start_mock_canvas_returning_port() -> Int

pub fn create_then_fetch_round_trip_test() {
  let port = start_mock_canvas_returning_port()
  let canvas =
    canvas.new(
      domain: "http://127.0.0.1:" <> int.to_string(port) <> "/api/v1",
      token: "mock-token",
    )

  let assert Ok(template) =
    questions.load(filepath: "questions.toml", palette: questions.no_color())

  let params =
    quiz.Create(
      title: option.Some("Week 9"),
      description: option.None,
      quiz_type: option.Some(quiz.GradedSurvey),
      assignment_group_id: option.None,
      points_possible: option.None,
    )

  let assert Ok(Nil) =
    create.create_per_group(
      canvas:,
      course_id: 101,
      params:,
      template:,
      due_at: option.None,
      unlock_at: option.None,
      published: False,
    )

  let results_path = "build/e2e_results.csv"
  let assert Ok(Nil) =
    eval.fetch_student_ratings(
      canvas:,
      course_id: 101,
      filepath: results_path,
      template:,
      title_prefix: "Week ",
    )

  let rating_when_every_rater_distributes_evenly =
    template.distribute.points_per_member
    |> int.to_float
    |> float.to_string

  read_rows(results_path)
  |> should.equal(
    [
      #("Group Alpha", "Alice Anderson"),
      #("Group Alpha", "Bob Brown"),
      #("Group Alpha", "Carol Clarke"),
      #("Group Beta", "Dave Dunn"),
      #("Group Beta", "Erin Estrada"),
    ]
    |> list.map(fn(row) {
      dict.from_list([
        #("Group Name", row.0),
        #("Name", row.1),
        #("Week 9", rating_when_every_rater_distributes_evenly),
      ])
    }),
  )

  let percent_path = "build/e2e_percent.csv"
  let assert Ok(Nil) =
    fetch.percent_completed(
      canvas:,
      course_id: 101,
      filepath: percent_path,
      title_prefix: "Week ",
    )

  let quizzes_per_student = 1
  let quizzes_total = 2
  let percent_when_each_student_submits_only_their_group_quiz =
    int.to_float(quizzes_per_student) /. int.to_float(quizzes_total)
    |> float.to_string

  read_rows(percent_path)
  |> list.sort(fn(a, b) { string.compare(name_of(a), name_of(b)) })
  |> should.equal(
    [
      #("Alice Anderson", 1),
      #("Bob Brown", 2),
      #("Carol Clarke", 3),
      #("Dave Dunn", 4),
      #("Erin Estrada", 5),
    ]
    |> list.map(fn(row) {
      dict.from_list([
        #("Name", row.0),
        #("Student ID", int.to_string(row.1)),
        #("Quizzes Completed", int.to_string(quizzes_per_student)),
        #(
          "Percent Completed",
          percent_when_each_student_submits_only_their_group_quiz,
        ),
      ])
    }),
  )
}

fn read_rows(filepath: String) -> List(dict.Dict(String, String)) {
  let assert Ok(csv) = simplifile.read(filepath)
  let assert Ok(rows) = gsv.to_dicts(csv)
  rows
}

fn name_of(row: dict.Dict(String, String)) -> String {
  dict.get(row, "Name") |> result.unwrap("")
}
