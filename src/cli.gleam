import gleam/option
import gleam/result
import gleam/string

import argv
import birl
import clip
import clip/arg
import clip/help
import clip/opt

import canvas/courses
import canvas/form
import canvas/quiz

pub type Args {
  Create(
    course_id: Int,
    group_id: option.Option(Int),
    title: option.Option(String),
    description: option.Option(String),
    quiz_type: option.Option(quiz.QuizType),
    assignment_group_id: option.Option(Int),
    due_at: option.Option(birl.Time),
    unlock_at: option.Option(birl.Time),
    published: Bool,
    points_possible: option.Option(Int),
  )
  List(List)
  Fetch(course_id: Int, quiz_title: String)
  Write(course_id: Int, filepath: String)
}

pub type List {
  Courses(enrollment_type: courses.EnrollmentType)
  Groups(course_id: Int)
  AssignmentGroups(course_id: Int)
}

const cli_name = "cgq"

pub fn cli() -> Result(Args, String) {
  clip.subcommands([
    #("create", create()),
    #("list", list()),
    #("fetch", fetch()),
    #("write", write()),
  ])
  |> clip.help(help.simple(
    cli_name,
    "Create a group quiz or fetch quiz results",
  ))
  |> clip.run(argv.load().arguments)
}

pub fn create() -> clip.Command(Args) {
  clip.command({
    use course_id <- clip.parameter
    use group_id: option.Option(Int) <- clip.parameter
    use title <- clip.parameter
    use description <- clip.parameter
    use quiz_type <- clip.parameter
    use assignment_group_id <- clip.parameter
    use due_at <- clip.parameter
    use unlock_at <- clip.parameter
    use published <- clip.parameter
    use points_possible <- clip.parameter

    Create(
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
    )
  })
  |> clip.arg(
    arg.new("course_id")
    |> arg.help("The unique identifier for the course.")
    |> arg.int,
  )
  |> clip.opt(
    opt.new("group_id")
    |> opt.help("The unique identifier for a group.")
    |> opt.int
    |> opt.map(option.Some)
    |> opt.default(option.None),
  )
  |> clip.opt(
    opt.new("title")
    |> opt.help("The quiz title.")
    |> opt.map(option.Some)
    |> opt.default(option.None),
  )
  |> clip.opt(
    opt.new("description")
    |> opt.help("A description of the quiz.")
    |> opt.map(option.Some)
    |> opt.default(option.None),
  )
  |> clip.opt(
    opt.new("quiz_type")
    |> opt.help(
      "The type of quiz: practice_quiz, assignment, graded_survey, survey.",
    )
    |> opt.try_map({
      use param <- clip.parameter
      case param {
        "practice_quiz" -> quiz.PracticeQuiz |> option.Some |> Ok
        "assignment" -> quiz.Assignment |> option.Some |> Ok
        "graded_survey" -> quiz.GradedSurvey |> option.Some |> Ok
        "survey" -> quiz.Survey |> option.Some |> Ok
        _ -> Error("Unable to parse quiz type.")
      }
    })
    |> opt.default(option.None),
  )
  |> clip.opt(
    opt.new("assignment_group_id")
    |> opt.help("The assignment group id to put the assignment in.")
    |> opt.int
    |> opt.map(option.Some)
    |> opt.default(option.None),
  )
  |> clip.opt(
    opt.new("due_at")
    |> opt.help(
      "The day/time the quiz is due in ISO 8601 format, e.g. \"2025-03-01 23:59.999-8:00\".",
    )
    |> opt.try_map({
      use param <- clip.parameter
      param
      |> birl.parse
      |> result.map(option.Some)
      |> result.replace_error("Unable to parse datetime.")
    })
    |> opt.default(option.None),
  )
  |> clip.opt(
    opt.new("unlock_at")
    |> opt.help(
      "The day/time the quiz is unlocked in ISO 8601 format, e.g. \"2025-03-01 23:59.999-8:00\".",
    )
    |> opt.try_map({
      use param <- clip.parameter
      param
      |> birl.parse
      |> result.map(option.Some)
      |> result.replace_error("Unable to parse datetime.")
    })
    |> opt.default(option.None),
  )
  |> clip.opt(
    opt.new("published")
    |> opt.help("Whether the quiz should be published or unpublished.")
    |> opt.try_map({
      use opt <- clip.parameter
      case opt |> string.lowercase {
        "true" | "t" -> True |> Ok
        "false" | "f" -> False |> Ok
        _ -> Error("Unable to parse published.")
      }
    })
    |> opt.default(False),
  )
  |> clip.opt(
    opt.new("points_possible")
    |> opt.help("The total point value given to the quiz.")
    |> opt.int
    |> opt.map(option.Some)
    |> opt.default(option.None),
  )
  |> clip.help(help.simple(
    cli_name <> " create",
    "Create a new quiz for this course.",
  ))
}

pub fn list() -> clip.Command(Args) {
  clip.subcommands([
    #("courses", {
      clip.command({
        use enrollment_type <- form.parameter
        Courses(enrollment_type:) |> List
      })
      |> clip.arg(
        arg.new("enrollment_type")
        |> arg.try_map({
          use arg <- form.parameter

          case arg |> string.lowercase {
            "teacher" -> courses.Teacher |> Ok()
            "student" -> courses.Student |> Ok()
            "ta" -> courses.TA |> Ok()
            _ -> Error("Unable to parse enrollment_type.")
          }
        }),
      )
      |> clip.help(help.simple(
        cli_name <> " list courses",
        "List of your active courses.",
      ))
    }),
    #("groups", {
      clip.command({
        use course_id <- clip.parameter
        Groups(course_id:) |> List
      })
      |> clip.arg(
        arg.new("course_id")
        |> arg.help("The unique identifier for the course.")
        |> arg.int,
      )
      |> clip.help(help.simple(
        cli_name <> " list groups",
        "List of groups for the course.",
      ))
    }),
    #("assignment_groups", {
      clip.command({
        use course_id <- clip.parameter
        AssignmentGroups(course_id:) |> List
      })
      |> clip.arg(
        arg.new("course_id")
        |> arg.help("The unique identifier for the course.")
        |> arg.int,
      )
      |> clip.help(help.simple(
        cli_name <> " list assignment_groups",
        "List of assignment groups for the course.",
      ))
    }),
  ])
  |> clip.help(help.simple(
    cli_name <> " list",
    "List your courses, groups, or assignment groups for a course.",
  ))
}

fn fetch() -> clip.Command(Args) {
  clip.command({
    use course_id <- clip.parameter
    use quiz_title <- clip.parameter
    Fetch(course_id:, quiz_title:)
  })
  |> clip.arg(
    arg.new("course_id")
    |> arg.help("The unique identifier for the course.")
    |> arg.int,
  )
  |> clip.arg(
    arg.new("quiz_title")
    |> arg.help("The title used for creating the quiz."),
  )
  |> clip.help(help.simple(cli_name <> " fetch", "Fetch quiz results."))
}

fn write() -> clip.Command(Args) {
  clip.command({
    use course_id <- clip.parameter
    use filepath <- clip.parameter
    Write(course_id:, filepath:)
  })
  |> clip.arg(
    arg.new("course_id")
    |> arg.help("The unique identifier for the course.")
    |> arg.int,
  )
  |> clip.arg(
    arg.new("filepath")
    |> arg.default("./results.csv")
    |> arg.help("The filepath to save the results too."),
  )
  |> clip.help(help.simple(
    cli_name <> " write",
    "Write peer review evals to file",
  ))
}
