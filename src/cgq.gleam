import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string

import birl
import envoy

import canvas
import canvas/assignment_groups
import canvas/assignment_override
import canvas/courses
import canvas/form
import canvas/group
import canvas/question
import canvas/quiz
import cli
import table

pub type Error {
  FailedToGetArgs(String)
  FailedToGetEnvironmentVariables

  FailedToListGroups(canvas.Error)
  FailedToParseDate
  FailedToGetGroupUsers(canvas.Error)
  NoDueAt
  FailedToCreateQuiz(canvas.Error)
  FailedToCreateQuestion(canvas.Error)
  FailedToCreateAssignmentOverride(canvas.Error)
  FailedToEditAssignment(canvas.Error)

  FailedToListCourses(canvas.Error)
  FailedToListAssignmentGroups(canvas.Error)
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
        title:,
        description:,
        quiz_type:,
        assignment_group_id:,
        due_at:,
        unlock_at:,
        published:,
      ) ->
        quiz.Create(
          title:,
          description:,
          quiz_type:,
          assignment_group_id:,
          published:,
        )
        |> create(canvas:, course_id:, params: _, due_at:, unlock_at:)
      cli.List(list) -> {
        case list {
          cli.Courses(enrollment_type:) ->
            list_courses(canvas:, enrollment_type:)
          cli.AssignmentGroups(course_id:) ->
            list_assignment_groups(canvas:, course_id:)
        }
      }
    }
  }
  |> result.map_error({
    use err <- form.parameter
    err |> string.inspect |> io.println_error
    err
  })
}

fn create(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  params params: quiz.QuizParams,
  due_at due_at: option.Option(birl.Time),
  unlock_at unlock_at: option.Option(birl.Time),
) {
  use groups <- result.try(
    group.list_groups(canvas, course_id:)
    |> result.map_error(FailedToListGroups),
  )

  // TODO: switch back to mapping
  use group <- result.try(
    list.first(groups) |> result.replace_error(FailedToParseDate),
  )
  //use group <- list.map(groups)
  let group_name = group.name

  io.println("Creating quiz for group " <> group_name <> "...")

  use students <- result.try(
    group.list_group_users(canvas, group.id)
    |> result.map_error(FailedToGetGroupUsers),
  )

  let student_ids = {
    use student <- list.map(students)
    student.id
  }

  let student_names = {
    use student <- list.map(students)
    student.name
  }

  use quiz <- result.try(
    params
    |> quiz.create_new_quiz(canvas:, course_id:)
    |> result.map_error(FailedToCreateQuiz),
  )
  let quiz_id = quiz.id
  let assignment_id = quiz.assignment_id

  io.println(
    "Created quiz with ID "
    <> int.to_string(quiz_id)
    <> " and assignment ID "
    <> int.to_string(assignment_id)
    <> ".  Adding quiz questions...",
  )

  use _ <- result.try(create_question(
    canvas:,
    course_id:,
    quiz_id:,
    student_names:,
  ))

  io.println("Questions created.  Assigning quiz to group...")

  use _ <- result.map(
    assignment_override.AssignmentOverride(
      assignment_id:,
      quiz_id:,
      student_ids:,
      due_at:,
      unlock_at:,
    )
    |> assignment_override.create_assignment_override(
      canvas:,
      course_id:,
      assignment_override: _,
    )
    |> result.map_error(FailedToCreateAssignmentOverride),
  )

  io.println("Quiz assigned.")
}

fn create_question(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  quiz_id quiz_id: Int,
  student_names student_names: List(String),
) {
  let questions =
    [
      [
        question.Numerical(
          text: "How many issues did you have assigned this week?",
          points: option.Some(1),
        ),
        question.Numerical(
          text: "How many issues did you complete this week?",
          points: option.Some(1),
        ),
        question.Text(
          text: "Based on this week, you need to distribute "
          <> int.to_string(list.length(student_names) * 3)
          <> " points between your team members (including yourself) in the following "
          <> int.to_string(list.length(student_names))
          <> " questions. Ensure the points add up correctly.",
        ),
      ],
      list.map(student_names, {
        use name <- form.parameter
        question.Numerical(
          text: "The points distributed for " <> name,
          points: option.Some(1),
        )
      }),
      [
        question.Essay(
          text: "(Optional) Please add any other comment you think the Professor should know about this week's progress."
            <> "  For example, any blockers, conflicts within the team, etc.",
          points: option.None,
        ),
      ],
    ]
    |> list.flatten

  use _, question <- list.try_fold(questions, Nil)
  question.create_new_question(canvas:, course_id:, quiz_id:, question:)
  |> result.map_error(FailedToCreateQuestion)
}

fn list_courses(
  canvas canvas: canvas.Canvas,
  enrollment_type enrollment_type: courses.EnrollmentType,
) {
  use courses <- result.map(
    courses.list_courses(canvas:, enrollment_type:)
    |> result.map_error(FailedToListCourses),
  )

  let courses = {
    use course <- list.filter_map(courses)
    use name <- result.map(option.to_result(course.name, Nil))
    #(course.id, name |> string.trim)
  }

  table.table(courses)
  |> table.with("Name", table.Left, {
    use #(_, name) <- table.param
    name
  })
  |> table.with("ID", table.Right, {
    use #(id, _) <- table.param
    id
    |> int.to_string
  })
  |> table.print
}

fn list_assignment_groups(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
) {
  use assignment_groups <- result.map(
    assignment_groups.list_assignment_groups(canvas:, course_id:)
    |> result.map_error(FailedToListAssignmentGroups),
  )

  table.table(assignment_groups)
  |> table.with("Name", table.Left, {
    use assignment_groups.AssignmentGroup(name:, id: _) <- table.param
    name
  })
  |> table.with("ID", table.Right, {
    use assignment_groups.AssignmentGroup(name: _, id:) <- table.param
    id |> int.to_string
  })
  |> table.print
}
