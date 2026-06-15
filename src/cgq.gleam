import gleam/io
import gleam/option
import gleam/result

import envoy

import canvas
import canvas/quiz
import cgq/create as cgq_create
import cgq/eval as cgq_eval
import cgq/fetch as cgq_fetch
import cgq/list as cgq_list
import cgq/questions as cgq_questions
import cgq/report
import cli

pub type Error {
  FailedToGetArgs(String)
  FailedToGetEnvironmentVariables
  FailedToCreate(cgq_create.Error)
  FailedToList(cgq_list.Error)
  FailedToFetch(cgq_fetch.Error)
  FailedToEval(cgq_eval.Error)
  FailedToLoadQuestions(rendered: String)
}

pub fn main() -> Nil {
  let palette = stderr_palette()

  let outcome = {
    use arg <- result.try(cli.cli() |> result.map_error(FailedToGetArgs))

    case arg {
      cli.Validate(questions:) -> validate(filepath: questions, palette:)
      _ -> dispatch_with_canvas(arg:, palette:)
    }
  }

  case result.map_error(outcome, fn(error) { print_error(error, palette) }) {
    Ok(Nil) -> Nil
    Error(_) -> halt(exit_code_failure)
  }
}

const exit_code_failure = 1

@external(erlang, "erlang", "halt")
fn halt(status status: Int) -> Nil

@external(erlang, "cgq_ffi", "stderr_is_terminal")
fn stderr_is_terminal() -> Bool

fn stderr_palette() -> cgq_questions.Palette {
  let disabled = result.is_ok(envoy.get("NO_COLOR"))
  let forced = result.is_ok(envoy.get("CLICOLOR_FORCE"))

  case disabled, forced || stderr_is_terminal() {
    False, True -> cgq_questions.ansi_color()
    _, _ -> cgq_questions.no_color()
  }
}

fn validate(
  filepath filepath: String,
  palette palette: cgq_questions.Palette,
) -> Result(Nil, Error) {
  use _template <- result.map(
    cgq_questions.load(filepath:, palette:)
    |> result.map_error(FailedToLoadQuestions),
  )
  io.println("✓ " <> filepath <> " is a valid question template.")
}

fn dispatch_with_canvas(
  arg arg: cli.Args,
  palette palette: cgq_questions.Palette,
) -> Result(Nil, Error) {
  use canvas <- result.try(canvas_from_env())

  case arg {
    cli.Create(
      course_id:,
      group_id:,
      group_category_id:,
      title:,
      description:,
      quiz_type:,
      assignment_group_id:,
      due_at:,
      unlock_at:,
      published:,
      points_possible:,
      questions:,
    ) -> {
      use template <- result.try(
        cgq_questions.load(filepath: questions, palette:)
        |> result.map_error(FailedToLoadQuestions),
      )
      let params =
        quiz.Create(
          title:,
          description:,
          quiz_type:,
          assignment_group_id:,
          points_possible:,
        )
      case group_id {
        option.Some(group_id) ->
          cgq_create.create_for_group(
            canvas:,
            course_id:,
            group_id:,
            params:,
            template:,
            due_at:,
            unlock_at:,
            published:,
          )
        option.None ->
          cgq_create.create_per_group(
            canvas:,
            course_id:,
            group_category_id:,
            params:,
            template:,
            due_at:,
            unlock_at:,
            published:,
          )
      }
      |> result.map_error(FailedToCreate)
    }
    cli.List(list) ->
      case list {
        cli.Courses(enrollment_type:) ->
          cgq_list.courses(canvas:, enrollment_type:)
        cli.AssignmentGroups(course_id:) ->
          cgq_list.assignment_groups(canvas:, course_id:)
        cli.Groups(course_id:, group_category_id:) ->
          cgq_list.groups(canvas:, course_id:, group_category_id:)
        cli.GroupCategories(course_id:) ->
          cgq_list.group_categories(canvas:, course_id:)
      }
      |> result.map_error(FailedToList)
    cli.Fetch(fetch) ->
      case fetch {
        cli.Feedback(course_id:, quiz_title:) ->
          cgq_fetch.fetch(canvas:, course_id:, quiz_title:)
          |> result.map_error(FailedToFetch)
        cli.Evaluations(course_id:, filepath:, questions:, title_prefix:) -> {
          use template <- result.try(
            cgq_questions.load(filepath: questions, palette:)
            |> result.map_error(FailedToLoadQuestions),
          )
          cgq_eval.fetch_student_ratings(
            canvas:,
            course_id:,
            filepath:,
            template:,
            title_prefix:,
          )
          |> result.map_error(FailedToEval)
        }
        cli.PercentComplete(course_id:, filepath:, title_prefix:) ->
          cgq_fetch.percent_completed(
            canvas:,
            course_id:,
            filepath:,
            title_prefix:,
          )
          |> result.map_error(FailedToFetch)
      }
    cli.Validate(questions:) -> validate(filepath: questions, palette:)
  }
}

fn canvas_from_env() -> Result(canvas.Canvas, Error) {
  let domain =
    result.unwrap(
      envoy.get("CANVAS_API_DOMAIN"),
      "https://canvas.ubc.ca/api/v1",
    )
  use token <- result.map(
    envoy.get("CANVAS_API_TOKEN")
    |> result.replace_error(FailedToGetEnvironmentVariables),
  )
  canvas.new(domain:, token:)
}

fn print_error(
  error error: Error,
  palette palette: cgq_questions.Palette,
) -> Error {
  let output = case error {
    FailedToGetArgs(message) -> message
    FailedToLoadQuestions(rendered:) -> rendered
    FailedToGetEnvironmentVariables ->
      render(
        report.Report(
          message: "CANVAS_API_TOKEN is not set.",
          hint: option.Some(
            "Export your Canvas API token before running this command.",
          ),
        ),
        palette,
      )
    FailedToCreate(error) -> render(cgq_create.error_report(error), palette)
    FailedToList(error) -> render(cgq_list.error_report(error), palette)
    FailedToFetch(error) -> render(cgq_fetch.error_report(error), palette)
    FailedToEval(error) -> render(cgq_eval.error_report(error), palette)
  }
  io.println_error(output)
  error
}

fn render(
  failure failure: report.Report,
  palette palette: cgq_questions.Palette,
) -> String {
  cgq_questions.banner(message: failure.message, help: failure.hint, palette:)
}
