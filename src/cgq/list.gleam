import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import trellis/column

import trellis

import canvas
import canvas/assignment_groups
import canvas/courses
import canvas/group

pub type Error {
  FailedToListCourses(canvas.Error)
  FailedToListAssignmentGroups(canvas.Error)
  FailedToListGroups(canvas.Error)
}

pub fn courses(
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

  trellis.table(courses)
  |> trellis.with(
    column.new(header: "Name")
    |> column.align(column.Left)
    |> column.render({
      use #(_, name) <- trellis.param
      name
    }),
  )
  |> trellis.with(
    column.new(header: "ID")
    |> column.align(column.Left)
    |> column.render({
      use #(id, _) <- trellis.param
      id
      |> int.to_string
    }),
  )
  |> trellis.to_string
  |> io.println
}

pub fn assignment_groups(canvas canvas: canvas.Canvas, course_id course_id: Int) {
  use assignment_groups <- result.map(
    assignment_groups.list_assignment_groups(canvas:, course_id:)
    |> result.map_error(FailedToListAssignmentGroups),
  )

  trellis.table(assignment_groups)
  |> trellis.with(
    column.new(header: "Name")
    |> column.align(column.Left)
    |> column.render({
      use assignment_groups.AssignmentGroup(name:, id: _) <- trellis.param
      name
    }),
  )
  |> trellis.with(
    column.new(header: "ID")
    |> column.align(column.Right)
    |> column.render({
      use assignment_groups.AssignmentGroup(name: _, id:) <- trellis.param
      id |> int.to_string
    }),
  )
  |> trellis.to_string
  |> io.println
}

pub fn groups(canvas canvas: canvas.Canvas, course_id course_id: Int) {
  use groups <- result.map(
    group.list_groups(canvas:, course_id:)
    |> result.map_error(FailedToListGroups),
  )

  trellis.table(groups)
  |> trellis.with(
    column.new(header: "Name")
    |> column.align(column.Left)
    |> column.render({
      use group.Group(name:, id: _, members_count: _) <- trellis.param
      name
    }),
  )
  |> trellis.with(
    column.new(header: "ID")
    |> column.align(column.Left)
    |> column.render({
      use group.Group(name: _, id:, members_count: _) <- trellis.param
      id |> int.to_string
    }),
  )
  |> trellis.with(
    column.new(header: "Members")
    |> column.align(column.Left)
    |> column.render({
      use group.Group(name: _, id: _, members_count:) <- trellis.param
      members_count |> int.to_string
    }),
  )
  |> trellis.to_string
  |> io.println
}
