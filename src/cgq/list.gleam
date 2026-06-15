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
import canvas/group_categories

import cgq/report

pub type Error {
  FailedToListCourses(canvas.Error)
  FailedToListAssignmentGroups(canvas.Error)
  FailedToListGroups(canvas.Error)
  FailedToListGroupCategories(canvas.Error)
}

pub fn error_report(error error: Error) -> report.Report {
  case error {
    FailedToListCourses(error) ->
      report.from_canvas("The courses could not be listed", error)
    FailedToListAssignmentGroups(error) ->
      report.from_canvas("The assignment groups could not be listed", error)
    FailedToListGroups(error) ->
      report.from_canvas("The groups could not be listed", error)
    FailedToListGroupCategories(error) ->
      report.from_canvas("The group sets could not be listed", error)
  }
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

pub fn assignment_groups(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
) {
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

pub fn group_categories(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
) {
  use categories <- result.map(
    group_categories.list_group_categories(canvas:, course_id:)
    |> result.map_error(FailedToListGroupCategories),
  )

  trellis.table(categories)
  |> trellis.with(
    column.new(header: "Name")
    |> column.align(column.Left)
    |> column.render({
      use group_categories.GroupCategory(name:, id: _) <- trellis.param
      name
    }),
  )
  |> trellis.with(
    column.new(header: "ID")
    |> column.align(column.Right)
    |> column.render({
      use group_categories.GroupCategory(name: _, id:) <- trellis.param
      id |> int.to_string
    }),
  )
  |> trellis.to_string
  |> io.println
}

pub fn groups(
  canvas canvas: canvas.Canvas,
  course_id course_id: Int,
  group_category_id group_category_id: option.Option(Int),
) {
  use groups <- result.map(
    case group_category_id {
      option.Some(group_category_id) ->
        group.list_groups_in_category(canvas:, group_category_id:)
      option.None -> group.list_groups(canvas:, course_id:)
    }
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
