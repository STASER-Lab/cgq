import gleam/bool
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/task
import gleam/result

import birl

import canvas
import canvas/assignment_override
import canvas/group
import canvas/quiz

import cgq/eval
import cgq/questions
import cgq/title

pub type Error {
  FailedToGetGroup(canvas.Error)
  FailedToGetGroups(canvas.Error)
  FailedToGetGroupUsers(canvas.Error)
  FailedToCreateQuiz(canvas.Error)
  FailedToCreateAssignmentOverride(canvas.Error)
  FailedToPublish(canvas.Error)
  FailedToCreateQuestion(canvas.Error)
  FailedTask(task.AwaitError)
}

pub fn create_per_group(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  group_category_id group_category_id: option.Option(Int),
  params params: quiz.QuizParams,
  template template: questions.Template,
  due_at due_at: option.Option(birl.Time),
  unlock_at unlock_at: option.Option(birl.Time),
  published published: Bool,
) -> Result(Nil, Error) {
  io.println("Creating quizzes for each group...")

  use groups <- result.try(
    case group_category_id {
      option.Some(group_category_id) ->
        group.list_groups_in_category(canvas:, group_category_id:)
      option.None -> group.list_groups(canvas:, course_id:)
    }
    |> result.map_error(FailedToGetGroups),
  )

  {
    use group <- list.map(groups)
    task.async(fn() {
      create(
        canvas:,
        course_id:,
        params:,
        template:,
        due_at:,
        unlock_at:,
        group:,
        published:,
      )
    })
  }
  |> task.try_await_all(100_000)
  |> result.all
  |> result.map_error(FailedTask)
  |> result.map(result.all)
  |> result.flatten
  |> result.replace(Nil)
}

pub fn create_for_group(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  group_id group_id: Int,
  params params: quiz.QuizParams,
  template template: questions.Template,
  due_at due_at: option.Option(birl.Time),
  unlock_at unlock_at: option.Option(birl.Time),
  published published: Bool,
) {
  use group <- result.try(
    group.get_group(canvas:, group_id:)
    |> result.map_error(FailedToGetGroup),
  )

  create(
    canvas:,
    course_id:,
    params:,
    template:,
    due_at:,
    unlock_at:,
    group:,
    published:,
  )
}

fn create(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  params params: quiz.QuizParams,
  template template: questions.Template,
  due_at due_at: option.Option(birl.Time),
  unlock_at unlock_at: option.Option(birl.Time),
  group group: group.Group,
  published published: Bool,
) {
  let group_name = group.name

  let params =
    quiz.Create(
      ..params,
      title: option.map(params.title, fn(base) {
        title.for_group(base:, group: group_name)
      }),
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

  use _ <- result.try(
    eval.create_question(
      canvas:,
      course_id:,
      quiz_id:,
      template:,
      student_names:,
    )
    |> result.map_error(FailedToCreateQuestion),
  )

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

  use <- bool.guard(when: !published, return: Ok(Nil))

  io.println("  Publishing...")

  use _ <- result.map(
    quiz.publish_quiz(canvas:, course_id:, quiz_id:)
    |> result.map_error(FailedToPublish),
  )

  io.println("Published.")
}
