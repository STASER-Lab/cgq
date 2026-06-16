import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option

import gleeunit
import gleeunit/should

import canvas
import canvas/question
import canvas/quiz
import canvas/submissions
import canvas/user
import cgq/create
import cgq/eval
import cgq/fetch
import cgq/pretty
import cgq/questions
import cgq/report
import cgq/title

pub fn main() {
  gleeunit.main()
}

fn template() -> questions.Template {
  let assert Ok(template) =
    questions.load(filepath: "questions.toml", palette: questions.no_color())
  template
}

// --- create side: the question template ---
// Freezes the exact questions sent to Canvas: the shipped questions.toml must
// reproduce the original hardcoded template byte-for-byte.

pub fn template_to_questions_test() {
  questions.to_questions(template: template(), student_names: [
    "Alice", "Bob", "Carol",
  ])
  |> should.equal([
    question.Numerical(
      "How many issues did you have assigned this week?",
      option.Some(1),
    ),
    question.Numerical(
      "How many issues did you complete this week?",
      option.Some(1),
    ),
    question.Text(
      "Based on this week, you need to distribute 9 points between your team members (including yourself) in the following 3 questions. Ensure the points add up correctly.",
    ),
    question.Numerical("The points distributed for Alice", option.Some(1)),
    question.Numerical("The points distributed for Bob", option.Some(1)),
    question.Numerical("The points distributed for Carol", option.Some(1)),
    question.Essay(
      "(Optional) Please add any other comment you think the Professor should know about this week's progress.  For example, any blockers, conflicts within the team, etc.",
      option.None,
    ),
  ])
}

// --- template parsing: the fetch-side contract ---

pub fn template_affixes_test() {
  let distribute = template().distribute

  distribute.points_per_member |> should.equal(3)

  questions.member_name_affixes(distribute:)
  |> should.equal(#("The points distributed for ", ""))
}

pub fn parse_accepts_name_anywhere_in_member_text_test() {
  let assert Ok(template) =
    "
  [[question]]
  type = \"distribute\"
  points_per_member = 3
  instruction = \"Distribute {points} points.\"
  member_text = \"Rate {name} out of 5\"
  "
    |> questions.parse

  questions.member_name_affixes(distribute: template.distribute)
  |> should.equal(#("Rate ", " out of 5"))
}

pub fn parse_rejects_missing_distribute_test() {
  "
  [[question]]
  type = \"essay\"
  text = \"Any comments?\"
  "
  |> questions.parse
  |> should.equal(Error(questions.TemplateMissingDistributeQuestion))
}

pub fn parse_rejects_member_text_without_name_test() {
  "
  [[question]]
  type = \"distribute\"
  points_per_member = 3
  instruction = \"Distribute {points} points.\"
  member_text = \"Points for the teammate\"
  "
  |> questions.parse
  |> should.equal(
    Error(questions.QuestionHasProblem(
      question_index: 0,
      problem: questions.MemberTextMustContainNamePlaceholder,
    )),
  )
}

pub fn parse_rejects_bare_name_member_text_test() {
  "
  [[question]]
  type = \"distribute\"
  points_per_member = 3
  instruction = \"Distribute {points} points.\"
  member_text = \"{name}\"
  "
  |> questions.parse
  |> should.equal(
    Error(questions.QuestionHasProblem(
      question_index: 0,
      problem: questions.MemberTextNeedsLiteralTextAroundName,
    )),
  )
}

pub fn parse_rejects_unknown_type_test() {
  "
  [[question]]
  type = \"multiple_guess\"
  text = \"Pick one\"
  "
  |> questions.parse
  |> should.equal(
    Error(questions.QuestionHasProblem(
      question_index: 0,
      problem: questions.UnknownType(found: "multiple_guess"),
    )),
  )
}

// --- fetch side: rating aggregation ---
// Freezes how points are parsed out of question text, rescaled per rater, and
// normalized per group. Prefixes and multiplier now come from questions.toml.

fn submission(
  group group: String,
  name name: String,
  total total: Int,
  distributed distributed: List(#(String, Int)),
) -> fetch.QuizSubmission {
  // Non-distribution numericals must be ignored by the parser.
  let issues = [
    #(
      question.Numerical(
        "How many issues did you have assigned this week?",
        option.Some(1),
      ),
      submissions.Answer(question_id: 0, text: "5"),
    ),
    #(
      question.Numerical(
        "How many issues did you complete this week?",
        option.Some(1),
      ),
      submissions.Answer(question_id: 0, text: "4"),
    ),
  ]

  let instruction = [
    #(
      question.Text(
        "Based on this week, you need to distribute "
        <> int.to_string(total)
        <> " points between your team members (including yourself).",
      ),
      submissions.Answer(question_id: 0, text: ""),
    ),
  ]

  let ratings = {
    use #(teammate, points) <- list.map(distributed)
    #(
      question.Numerical(
        "The points distributed for " <> teammate,
        option.Some(1),
      ),
      submissions.Answer(question_id: 0, text: int.to_string(points)),
    )
  }

  fetch.QuizSubmission(
    user: user.User(id: 0, name: name),
    quiz: quiz.Quiz(id: 1, assignment_id: 1, title: "Week 9: " <> group),
    q_and_a: list.flatten([issues, instruction, ratings]),
  )
}

fn ratings_for_week(
  subs subs: List(fetch.QuizSubmission),
) -> dict.Dict(#(String, String), Float) {
  let distribute = template().distribute
  eval.ratings_for_week(submissions: subs, distribute:)
}

fn rating(
  ratings ratings: dict.Dict(#(String, String), Float),
  group group: String,
  name name: String,
) -> Float {
  let assert Ok(value) = dict.get(ratings, #(group, name))
  value
}

fn close(actual actual: Float, expected expected: Float) -> Nil {
  { float.absolute_value(actual -. expected) <. 0.0001 }
  |> should.be_true
}

pub fn ratings_symmetric_test() {
  let even = [#("A", 3), #("B", 3), #("C", 3)]
  let ratings =
    ratings_for_week(subs: [
      submission(group: "Trio", name: "A", total: 9, distributed: even),
      submission(group: "Trio", name: "B", total: 9, distributed: even),
      submission(group: "Trio", name: "C", total: 9, distributed: even),
    ])

  close(actual: rating(ratings, "Trio", "A"), expected: 3.0)
  close(actual: rating(ratings, "Trio", "B"), expected: 3.0)
  close(actual: rating(ratings, "Trio", "C"), expected: 3.0)
}

pub fn ratings_asymmetric_test() {
  let skewed = [#("A", 1), #("B", 4), #("C", 4)]
  let ratings =
    ratings_for_week(subs: [
      submission(group: "Trio", name: "A", total: 9, distributed: skewed),
      submission(group: "Trio", name: "B", total: 9, distributed: skewed),
      submission(group: "Trio", name: "C", total: 9, distributed: skewed),
    ])

  close(actual: rating(ratings, "Trio", "A"), expected: 1.0)
  close(actual: rating(ratings, "Trio", "B"), expected: 4.0)
  close(actual: rating(ratings, "Trio", "C"), expected: 4.0)
}

pub fn ratings_rescales_under_distribution_test() {
  // Group total is 6 (2 members * 3). Rater B spends only 4 of 6 points; the
  // per-rater scale should still give B's relative split full weight.
  let ratings =
    ratings_for_week(subs: [
      submission(group: "Duo", name: "A", total: 6, distributed: [
        #("A", 1),
        #("B", 5),
      ]),
      submission(group: "Duo", name: "B", total: 6, distributed: [
        #("A", 2),
        #("B", 2),
      ]),
    ])

  close(actual: rating(ratings, "Duo", "A"), expected: 2.0)
  close(actual: rating(ratings, "Duo", "B"), expected: 4.0)
}

// --- fetch feedback: Canvas HTML to plain text, and blank detection ---

pub fn html_to_text_strips_tags_and_decodes_entities_test() {
  fetch.html_to_text(
    "<p>Build broke <strong>twice</strong> &amp; CI was red.</p>",
  )
  |> should.equal("Build broke twice & CI was red.")
}

pub fn html_to_text_keeps_paragraph_and_line_breaks_test() {
  fetch.html_to_text("<p>First.</p><p>Second<br>third</p>")
  |> should.equal("First.\nSecond\nthird")
}

pub fn html_to_text_ignores_tag_attributes_test() {
  fetch.html_to_text(
    "<p dir=\"ltr\">See the <a href=\"http://x\">link</a>.</p>",
  )
  |> should.equal("See the link.")
}

pub fn is_blank_feedback_detects_stock_replies_test() {
  ["", "<p></p>", "  NA  ", "<p>N/A</p>", "<p>none.</p>", "<p>No comments.</p>"]
  |> list.each(fn(blank) { fetch.is_blank_feedback(blank) |> should.be_true })
}

pub fn is_blank_feedback_keeps_real_feedback_test() {
  fetch.is_blank_feedback("<p>The deploy failed on Friday.</p>")
  |> should.be_false
}

// --- error rendering: cause, hint, and composed reports ---

pub fn canvas_error_summary_covers_statuses_test() {
  canvas.error_summary(canvas.FailedRequestStatus(401))
  |> should.equal("Canvas rejected the API token (401)")

  canvas.error_summary(canvas.FailedRequestStatus(403))
  |> should.equal("Canvas denied permission for this request (403)")

  canvas.error_summary(canvas.FailedRequestStatus(404))
  |> should.equal("the requested item was not found (404)")

  canvas.error_summary(canvas.FailedRequestStatus(429))
  |> should.equal("Canvas rate limited the request (429)")

  canvas.error_summary(canvas.FailedRequestStatus(503))
  |> should.equal("Canvas had a server error (503)")

  canvas.error_summary(canvas.FailedRequestStatus(418))
  |> should.equal("Canvas returned an unexpected status (418)")

  canvas.error_summary(canvas.FailedToMakeRequest)
  |> should.equal("the request URL could not be built")
}

pub fn canvas_error_hint_is_actionable_or_absent_test() {
  canvas.error_hint(canvas.FailedRequestStatus(401))
  |> should.equal(option.Some(
    "Check that CANVAS_API_TOKEN holds a valid token.",
  ))

  canvas.error_hint(canvas.FailedRequestStatus(404))
  |> should.equal(option.Some("Check the course, group, or quiz id."))

  canvas.error_hint(canvas.FailedRequestStatus(422))
  |> should.equal(option.None)

  canvas.error_hint(canvas.FailedToMakeRequest)
  |> should.equal(option.Some("Check that CANVAS_API_DOMAIN is a valid URL."))
}

pub fn report_from_canvas_joins_context_cause_and_hint_test() {
  report.from_canvas(context: "Context", error: canvas.FailedRequestStatus(401))
  |> should.equal(report.Report(
    message: "Context. Canvas rejected the API token (401)",
    hint: option.Some("Check that CANVAS_API_TOKEN holds a valid token."),
  ))
}

pub fn create_error_report_wording_test() {
  create.error_report(
    create.FailedToCreateQuiz(canvas.FailedRequestStatus(404)),
  )
  |> should.equal(report.Report(
    message: "The quiz could not be created. the requested item was not found (404)",
    hint: option.Some("Check the course, group, or quiz id."),
  ))
}

pub fn fetch_error_report_async_has_no_hint_test() {
  fetch.error_report(fetch.FailedAsync)
  |> should.equal(report.Report(
    message: "A fetch task did not finish.",
    hint: option.None,
  ))
}

// --- title convention shared by create and fetch ---

pub fn title_for_group_and_split_round_trip_test() {
  let joined = title.for_group(base: "Week 9", group: "The Stragglers")

  joined |> should.equal("Week 9: The Stragglers")

  title.split(joined)
  |> should.equal(title.Title(base: "Week 9", group: "The Stragglers"))
}

pub fn title_split_without_separator_falls_back_test() {
  title.split("plain title")
  |> should.equal(title.Title(base: "plain title", group: "plain title"))
}

// --- table tinting ---

pub fn pretty_frame_is_identity_without_colour_test() {
  let table = "╭──╮\n│ x │\n╰──╯"

  pretty.frame(rendered: table, palette: questions.no_color())
  |> should.equal(table)
}

pub fn pretty_frame_tints_box_characters_test() {
  let palette = questions.ansi_color()

  pretty.frame(rendered: "│", palette:)
  |> should.equal(palette.frame <> "│" <> palette.reset)
}
