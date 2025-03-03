import gleam/function
import gleam/io
import gleam/option
import gleam/result
import gleam/string

import envoy

import canvas
import canvas/form
import canvas/quiz
import cgq/create as cgq_create
import cgq/fetch as cgq_fetch
import cgq/list as cgq_list
import cli

pub type Error {
  FailedToGetArgs(String)
  FailedToGetEnvironmentVariables
  FailedToCreate(cgq_create.Error)
  FailedToList(cgq_list.Error)
  FailedToFetch(cgq_fetch.Error)
}

pub fn main() -> Result(Nil, Error) {
  {
    let domain =
      result.unwrap(
        envoy.get("CANVAS_API_DOMAIN"),
        "https://canvas.ubc.ca/api/v1",
      )
    use token <- result.try(
      envoy.get("CANVAS_API_TOKEN")
      |> result.replace_error(FailedToGetEnvironmentVariables),
    )

    let canvas = canvas.new(domain:, token:)

    use arg <- result.try(cli.cli() |> result.map_error(FailedToGetArgs))

    case arg {
      cli.Create(
        course_id:,
        group_id:,
        title:,
        description:,
        quiz_type:,
        assignment_group_id:,
        due_at:,
        unlock_at:,
        published:,
        points_possible:,
      ) -> {
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
              due_at:,
              unlock_at:,
              published:,
            )
          option.None ->
            cgq_create.create_per_group(
              canvas:,
              course_id:,
              params:,
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
          cli.Groups(course_id:) -> cgq_list.groups(canvas:, course_id:)
        }
        |> result.map_error(FailedToList)
      cli.Fetch(course_id:, quiz_title:) ->
        cgq_fetch.fetch(canvas:, course_id:, quiz_title:)
        |> result.map_error(FailedToFetch)
      cli.Write(course_id:, filepath:) ->
        cgq_fetch.fetch_student_ratings(canvas:, course_id:, filepath:)
        |> result.map_error(FailedToFetch)
    }
  }
  |> result.map_error(
    function.tap(_, {
      use err <- form.parameter
      case err {
        FailedToGetArgs(str) -> str
        _ ->
          "Failed with error of "
          <> err |> string.inspect
          <> ".  Please use -h to see the help menu."
      }
      |> io.println_error
    }),
  )
}
