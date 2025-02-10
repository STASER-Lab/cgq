import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result

import birl

import canvas
import canvas/assignment_override
import canvas/form
import canvas/group
import canvas/question
import canvas/quiz

pub type Error {
  FailedToGetGroup(canvas.Error)
  FailedToGetGroups(canvas.Error)
  FailedToGetGroupUsers(canvas.Error)
  FailedToCreateQuiz(canvas.Error)
  FailedToCreateAssignmentOverride(canvas.Error)
  FailedToPublish(canvas.Error)
  FailedToCreateQuestion(canvas.Error)
}

pub fn create_per_group(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  params params: quiz.QuizParams,
  due_at due_at: option.Option(birl.Time),
  unlock_at unlock_at: option.Option(birl.Time),
  published published: option.Option(Bool),
) -> Result(Nil, Error) {
  use groups <- result.try(
    group.list_groups(canvas, course_id:)
    |> result.map_error(FailedToGetGroups),
  )

  {
    use group <- list.map(groups)

    create(
      canvas:,
      course_id:,
      params:,
      due_at:,
      unlock_at:,
      group:,
      published:,
    )
  }
  |> result.all
  |> result.replace(Nil)
}

pub fn create_for_group(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  group_id group_id: Int,
  params params: quiz.QuizParams,
  due_at due_at: option.Option(birl.Time),
  unlock_at unlock_at: option.Option(birl.Time),
  published published: option.Option(Bool),
) {
  use group <- result.try(
    group.get_group(canvas:, group_id:)
    |> result.map_error(FailedToGetGroup),
  )

  create(canvas:, course_id:, params:, due_at:, unlock_at:, group:, published:)
}

fn create(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  params params: quiz.QuizParams,
  due_at due_at: option.Option(birl.Time),
  unlock_at unlock_at: option.Option(birl.Time),
  group group: group.Group,
  published published: option.Option(Bool),
) {
  let group_name = group.name

  let params =
    quiz.Create(
      ..params,
      title: option.map(params.title, fn(title) { title <> ": " <> group_name }),
    )

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

  use _ <- result.try(
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

  io.print("Quiz assigned.")

  case published {
    option.Some(_) -> {
      io.println("  Publishing...")

      use _ <- result.map(
        quiz.publish_quiz(canvas:, course_id:, quiz_id:)
        |> result.map_error(FailedToPublish),
      )

      io.println("Published.")
    }
    option.None -> Ok(Nil)
  }
}

fn create_question(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  quiz_id quiz_id: Int,
  student_names student_names: List(String),
) -> Result(Nil, Error) {
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
