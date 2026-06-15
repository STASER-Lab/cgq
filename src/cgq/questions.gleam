import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string

import simplifile
import tom

import canvas/question

const points_placeholder = "{points}"

const count_placeholder = "{count}"

const name_placeholder = "{name}"

pub type Error {
  FailedToReadFile(reason: simplifile.FileError)
  FailedToParseToml(reason: tom.ParseError)
  MissingQuestionTables
  TemplateMissingDistributeQuestion
  TemplateHasMultipleDistributeQuestions(second_question_index: Int)
  QuestionHasProblem(question_index: Int, problem: Problem)
}

pub type Problem {
  NotATable
  MissingStringField(key: String)
  MissingIntegerField(key: String)
  FieldMustBeInteger(key: String)
  UnknownType(found: String)
  PointsPerMemberMustBePositive
  MemberTextMustContainNamePlaceholder
  MemberTextNeedsLiteralTextAroundName
}

pub type Distribute {
  Distribute(
    points_per_member: Int,
    member_points: option.Option(Int),
    instruction: String,
    member_text: String,
  )
}

pub type Template {
  Template(
    questions_before_distribute: List(question.Question),
    distribute: Distribute,
    questions_after_distribute: List(question.Question),
  )
}

pub fn load(
  filepath filepath: String,
  palette palette: Palette,
) -> Result(Template, String) {
  case simplifile.read(filepath) {
    Error(reason) ->
      Error(render(
        error: FailedToReadFile(reason:),
        source: "",
        filepath:,
        palette:,
      ))
    Ok(source) ->
      parse(toml: source)
      |> result.map_error(fn(error) {
        render(error:, source:, filepath:, palette:)
      })
  }
}

pub fn parse(toml toml: String) -> Result(Template, Error) {
  use parsed <- result.try(
    tom.parse(toml)
    |> result.map_error(FailedToParseToml),
  )

  use tables <- result.try(
    tom.get_array(parsed, ["question"])
    |> result.replace_error(MissingQuestionTables),
  )

  use parsed_questions <- result.try({
    use #(table, index) <- list.try_map(list.index_map(tables, with_index))
    use table <- result.try(
      tom.as_table(table)
      |> result.replace_error(QuestionHasProblem(index, NotATable)),
    )
    use parsed <- result.map(
      parse_question(table)
      |> result.map_error(QuestionHasProblem(index, _)),
    )
    #(parsed, index)
  })

  template_from(parsed_questions)
}

pub type Palette {
  Palette(
    title: String,
    frame: String,
    mark: String,
    hint: String,
    add: String,
    del: String,
    reset: String,
  )
}

pub fn no_color() -> Palette {
  Palette(title: "", frame: "", mark: "", hint: "", add: "", del: "", reset: "")
}

pub fn ansi_color() -> Palette {
  Palette(
    title: "\u{1b}[1;31m",
    frame: "\u{1b}[90m",
    mark: "\u{1b}[1;33m",
    hint: "\u{1b}[36m",
    add: "\u{1b}[32m",
    del: "\u{1b}[31m",
    reset: "\u{1b}[0m",
  )
}

pub fn render(
  error error: Error,
  source source: String,
  filepath filepath: String,
  palette palette: Palette,
) -> String {
  let Diagnostic(message:, frame:, help:) = diagnostic(error)

  case frame {
    NoFrame -> banner(message:, help:, palette:)
    QuestionFrame(index:, edit:) ->
      case question_block(source:, question_index: index) {
        Error(Nil) -> banner(message:, help:, palette:)
        Ok(block) ->
          render_frame(
            filepath:,
            question_index: index,
            block:,
            message:,
            edit:,
            help:,
            palette:,
          )
      }
  }
}

pub fn to_questions(
  template template: Template,
  student_names student_names: List(String),
) -> List(question.Question) {
  let Template(
    questions_before_distribute:,
    distribute:,
    questions_after_distribute:,
  ) = template

  list.flatten([
    questions_before_distribute,
    expand_distribute(distribute:, student_names:),
    questions_after_distribute,
  ])
}

pub fn member_name_affixes(
  distribute distribute: Distribute,
) -> #(String, String) {
  let assert Ok(affixes) =
    string.split_once(distribute.member_text, name_placeholder)
    as "parse_distribute guarantees member_text contains {name}"
  affixes
}

fn expand_distribute(
  distribute distribute: Distribute,
  student_names student_names: List(String),
) -> List(question.Question) {
  let Distribute(points_per_member:, member_points:, instruction:, member_text:) =
    distribute

  let count = list.length(student_names)
  let total = count * points_per_member

  let instruction =
    instruction
    |> string.replace(points_placeholder, int.to_string(total))
    |> string.replace(count_placeholder, int.to_string(count))

  let members = {
    use name <- list.map(student_names)
    question.Numerical(
      text: string.replace(member_text, name_placeholder, name),
      points: member_points,
    )
  }

  [question.Text(text: instruction), ..members]
}

type ParsedQuestion {
  StaticQuestion(question.Question)
  DistributeQuestion(Distribute)
}

fn with_index(item: a, index: Int) -> #(a, Int) {
  #(item, index)
}

fn template_from(
  parsed_questions: List(#(ParsedQuestion, Int)),
) -> Result(Template, Error) {
  let split = {
    use acc, #(parsed, index) <- list.try_fold(
      parsed_questions,
      #([], option.None, []),
    )
    let #(before, seen_distribute, after) = acc

    case parsed, seen_distribute {
      DistributeQuestion(_), option.Some(_) ->
        Error(TemplateHasMultipleDistributeQuestions(
          second_question_index: index,
        ))
      DistributeQuestion(distribute), option.None ->
        Ok(#(before, option.Some(distribute), after))
      StaticQuestion(question), option.None ->
        Ok(#([question, ..before], seen_distribute, after))
      StaticQuestion(question), option.Some(_) ->
        Ok(#(before, seen_distribute, [question, ..after]))
    }
  }

  use #(before, seen_distribute, after) <- result.try(split)

  case seen_distribute {
    option.None -> Error(TemplateMissingDistributeQuestion)
    option.Some(distribute) ->
      Template(
        questions_before_distribute: list.reverse(before),
        distribute:,
        questions_after_distribute: list.reverse(after),
      )
      |> Ok
  }
}

fn parse_question(
  table: dict.Dict(String, tom.Toml),
) -> Result(ParsedQuestion, Problem) {
  use question_type <- result.try(required_string(table, "type"))

  case question_type {
    "numerical" -> {
      use text <- result.try(required_string(table, "text"))
      use points <- result.map(optional_int(table, "points"))
      StaticQuestion(question.Numerical(text:, points:))
    }
    "essay" -> {
      use text <- result.try(required_string(table, "text"))
      use points <- result.map(optional_int(table, "points"))
      StaticQuestion(question.Essay(text:, points:))
    }
    "text" -> {
      use text <- result.map(required_string(table, "text"))
      StaticQuestion(question.Text(text:))
    }
    "distribute" -> parse_distribute(table)
    found -> Error(UnknownType(found:))
  }
}

fn parse_distribute(
  table: dict.Dict(String, tom.Toml),
) -> Result(ParsedQuestion, Problem) {
  use points_per_member <- result.try(required_int(table, "points_per_member"))
  use member_points <- result.try(optional_int(table, "member_points"))
  use instruction <- result.try(required_string(table, "instruction"))
  use member_text <- result.try(required_string(table, "member_text"))

  use <- ensure(points_per_member >= 1, PointsPerMemberMustBePositive)
  use <- ensure(
    string.contains(member_text, name_placeholder),
    MemberTextMustContainNamePlaceholder,
  )
  use <- ensure(
    member_text != name_placeholder,
    MemberTextNeedsLiteralTextAroundName,
  )

  DistributeQuestion(Distribute(
    points_per_member:,
    member_points:,
    instruction:,
    member_text:,
  ))
  |> Ok
}

fn ensure(
  that that: Bool,
  otherwise otherwise: Problem,
  continue continue: fn() -> Result(a, Problem),
) -> Result(a, Problem) {
  case that {
    True -> continue()
    False -> Error(otherwise)
  }
}

fn required_string(
  table: dict.Dict(String, tom.Toml),
  key: String,
) -> Result(String, Problem) {
  tom.get_string(table, [key])
  |> result.replace_error(MissingStringField(key:))
}

fn required_int(
  table: dict.Dict(String, tom.Toml),
  key: String,
) -> Result(Int, Problem) {
  tom.get_int(table, [key])
  |> result.replace_error(MissingIntegerField(key:))
}

fn optional_int(
  table: dict.Dict(String, tom.Toml),
  key: String,
) -> Result(option.Option(Int), Problem) {
  case tom.get_int(table, [key]) {
    Ok(value) -> option.Some(value) |> Ok
    Error(tom.NotFound(_)) -> option.None |> Ok
    Error(tom.WrongType(..)) -> Error(FieldMustBeInteger(key:))
  }
}

type Diagnostic {
  Diagnostic(message: String, frame: Frame, help: option.Option(String))
}

type Frame {
  NoFrame
  QuestionFrame(index: Int, edit: Edit)
}

type Edit {
  HighlightField(field: String)
  InsertField(line: String)
  ReplaceField(field: String, line: String)
}

fn diagnostic(error: Error) -> Diagnostic {
  case error {
    FailedToReadFile(reason:) ->
      Diagnostic(
        message: "could not read template file ("
          <> string.inspect(reason)
          <> ")",
        frame: NoFrame,
        help: option.Some("check the path passed to --questions"),
      )
    FailedToParseToml(tom.Unexpected(got:, expected:)) ->
      Diagnostic(
        message: "invalid TOML: unexpected "
          <> quoted(printable(got))
          <> ", expected "
          <> printable(expected),
        frame: NoFrame,
        help: option.None,
      )
    FailedToParseToml(tom.KeyAlreadyInUse(key:)) ->
      Diagnostic(
        message: "invalid TOML: duplicate key " <> quoted(string.join(key, ".")),
        frame: NoFrame,
        help: option.None,
      )
    MissingQuestionTables ->
      Diagnostic(
        message: "template has no [[question]] entries",
        frame: NoFrame,
        help: option.Some("add at least one [[question]] table"),
      )
    TemplateMissingDistributeQuestion ->
      Diagnostic(
        message: "template has no distribute question",
        frame: NoFrame,
        help: option.Some(
          "exactly one [[question]] must set type = \"distribute\"",
        ),
      )
    TemplateHasMultipleDistributeQuestions(second_question_index:) ->
      Diagnostic(
        message: "template has more than one distribute question",
        frame: QuestionFrame(
          index: second_question_index,
          edit: HighlightField("type"),
        ),
        help: option.Some(
          "a template must have exactly one type = \"distribute\" question",
        ),
      )
    QuestionHasProblem(question_index:, problem:) ->
      Diagnostic(
        message: problem_message(problem),
        frame: QuestionFrame(index: question_index, edit: edit_for(problem)),
        help: option.Some(help_for(problem)),
      )
  }
}

fn problem_message(problem: Problem) -> String {
  case problem {
    NotATable -> "question must be a TOML table"
    MissingStringField(key:) -> "missing required field " <> quoted(key)
    MissingIntegerField(key:) -> "missing required field " <> quoted(key)
    FieldMustBeInteger(key:) -> "field " <> quoted(key) <> " must be an integer"
    UnknownType(found:) -> "unknown question type " <> quoted(found)
    PointsPerMemberMustBePositive -> "points_per_member must be at least 1"
    MemberTextMustContainNamePlaceholder ->
      "member_text must contain " <> quoted("{name}")
    MemberTextNeedsLiteralTextAroundName ->
      "member_text must have literal text around " <> quoted("{name}")
  }
}

fn edit_for(problem: Problem) -> Edit {
  case problem {
    MissingStringField(key:) -> InsertField(key <> " = \"...\"")
    MissingIntegerField(key:) -> InsertField(key <> " = 0")
    FieldMustBeInteger(key:) -> ReplaceField(field: key, line: key <> " = 1")
    PointsPerMemberMustBePositive ->
      ReplaceField(field: "points_per_member", line: "points_per_member = 3")
    UnknownType(_) -> HighlightField("type")
    MemberTextMustContainNamePlaceholder -> HighlightField("member_text")
    MemberTextNeedsLiteralTextAroundName -> HighlightField("member_text")
    NotATable -> HighlightField("type")
  }
}

fn help_for(problem: Problem) -> String {
  case problem {
    MissingStringField(key:) ->
      "every question needs a " <> quoted(key) <> " field"
    MissingIntegerField(key:) ->
      "every question needs a " <> quoted(key) <> " field"
    FieldMustBeInteger(key:) -> quoted(key) <> " must be a whole number"
    UnknownType(_) -> "use one of: numerical, essay, text, distribute"
    PointsPerMemberMustBePositive -> "each teammate is worth at least 1 point"
    MemberTextMustContainNamePlaceholder ->
      "{name} is replaced with each teammate's name, e.g. \"Points for {name}\""
    MemberTextNeedsLiteralTextAroundName ->
      "fetch finds these questions by the literal text around {name}"
    NotATable -> "each [[question]] must be a table"
  }
}

fn banner(
  message message: String,
  help help: option.Option(String),
  palette palette: Palette,
) -> String {
  let header = paint(palette.title, "✗ " <> message, palette.reset)
  case help {
    option.Some(text) ->
      header <> "\n\n" <> paint(palette.hint, "  help: " <> text, palette.reset)
    option.None -> header
  }
}

fn render_frame(
  filepath filepath: String,
  question_index question_index: Int,
  block block: List(#(Int, String)),
  message message: String,
  edit edit: Edit,
  help help: option.Option(String),
  palette palette: Palette,
) -> String {
  let width =
    block
    |> list.map(fn(row) { string.length(int.to_string(row.0)) })
    |> list.fold(1, int.max)
  let pad = string.repeat(" ", width)
  let gutter = gutter_bar(pad:, palette:)

  let top =
    pad
    <> " "
    <> paint(
      palette.frame,
      "╭─[ "
        <> filepath
        <> " · question "
        <> int.to_string(question_index + 1)
        <> " ]",
      palette.reset,
    )

  let body = annotate_block(block:, message:, edit:, width:, palette:)

  let footer = case help {
    option.Some(text) ->
      pad
      <> " "
      <> paint(palette.frame, "╰─ ", palette.reset)
      <> paint(palette.hint, "help: " <> text, palette.reset)
    option.None -> pad <> " " <> paint(palette.frame, "╰─", palette.reset)
  }

  string.join(list.flatten([[top, gutter], body, [gutter, footer]]), "\n")
}

fn annotate_block(
  block block: List(#(Int, String)),
  message message: String,
  edit edit: Edit,
  width width: Int,
  palette palette: Palette,
) -> List(String) {
  case edit {
    HighlightField(field:) -> {
      use #(number, text) <- list.flat_map(block)
      let row = context_row(number:, text:, width:, palette:)
      case line_declares_field(text:, field:) {
        True -> [row, ..pointer_rows(text:, width:, message:, palette:)]
        False -> [row]
      }
    }
    InsertField(line:) -> {
      let context = {
        use #(number, text) <- list.map(block)
        context_row(number:, text:, width:, palette:)
      }
      let next =
        block
        |> list.last
        |> result.map(fn(row) { row.0 + 1 })
        |> result.unwrap(1)
      list.flatten([
        context,
        [
          change_row(
            number: next,
            marker: "+",
            color: palette.add,
            line:,
            width:,
            palette:,
          ),
        ],
        pointer_rows(text: line, width:, message:, palette:),
      ])
    }
    ReplaceField(field:, line:) -> {
      use #(number, text) <- list.flat_map(block)
      case line_declares_field(text:, field:) {
        True ->
          list.flatten([
            [
              change_row(
                number:,
                marker: "-",
                color: palette.del,
                line: text,
                width:,
                palette:,
              ),
            ],
            pointer_rows(text:, width:, message:, palette:),
            [
              change_row(
                number:,
                marker: "+",
                color: palette.add,
                line:,
                width:,
                palette:,
              ),
            ],
          ])
        False -> [context_row(number:, text:, width:, palette:)]
      }
    }
  }
}

fn gutter_bar(pad pad: String, palette palette: Palette) -> String {
  pad <> " " <> paint(palette.frame, "│", palette.reset)
}

fn context_row(
  number number: Int,
  text text: String,
  width width: Int,
  palette palette: Palette,
) -> String {
  let label = string.pad_start(int.to_string(number), to: width, with: " ")
  paint(palette.frame, label <> " │ ", palette.reset) <> text
}

fn change_row(
  number number: Int,
  marker marker: String,
  color color: String,
  line line: String,
  width width: Int,
  palette palette: Palette,
) -> String {
  let label = string.pad_start(int.to_string(number), to: width, with: " ")
  paint(palette.frame, label, palette.reset)
  <> " "
  <> paint(color, marker <> " " <> line, palette.reset)
}

fn pointer_rows(
  text text: String,
  width width: Int,
  message message: String,
  palette palette: Palette,
) -> List(String) {
  let leading = string.length(text) - string.length(string.trim_start(text))
  let span = string.length(string.trim(text))
  let underline = "┬" <> string.repeat("─", int.max(span - 1, 0))
  let stem =
    string.repeat(" ", width)
    <> " "
    <> paint(palette.frame, "· ", palette.reset)
    <> string.repeat(" ", leading)

  [
    stem <> paint(palette.mark, underline, palette.reset),
    stem
      <> paint(palette.mark, "╰── ", palette.reset)
      <> paint(palette.title, message, palette.reset),
  ]
}

fn line_declares_field(text text: String, field field: String) -> Bool {
  let trimmed = string.trim_start(text)
  string.starts_with(trimmed, field <> " ")
  || string.starts_with(trimmed, field <> "=")
}

fn question_block(
  source source: String,
  question_index question_index: Int,
) -> Result(List(#(Int, String)), Nil) {
  let numbered =
    string.split(source, "\n")
    |> list.index_map(fn(line, line_index) { #(line_index + 1, line) })

  let header_lines =
    numbered
    |> list.filter(fn(row) { string.trim(row.1) == "[[question]]" })
    |> list.map(fn(row) { row.0 })

  use start_line <- result.try(
    header_lines |> list.drop(question_index) |> list.first,
  )

  let end_line = case
    header_lines |> list.drop(question_index + 1) |> list.first
  {
    Ok(next_header) -> next_header - 1
    Error(Nil) -> list.length(numbered)
  }

  numbered
  |> list.filter(fn(row) { row.0 >= start_line && row.0 <= end_line })
  |> drop_trailing_blank_lines
  |> Ok
}

fn drop_trailing_blank_lines(
  rows: List(#(Int, String)),
) -> List(#(Int, String)) {
  rows
  |> list.reverse
  |> list.drop_while(fn(row) { string.trim(row.1) == "" })
  |> list.reverse
}

fn paint(
  color color: String,
  text text: String,
  reset reset: String,
) -> String {
  color <> text <> reset
}

fn quoted(text: String) -> String {
  "`" <> text <> "`"
}

fn printable(text: String) -> String {
  text
  |> string.replace("\n", "\\n")
  |> string.replace("\t", "\\t")
  |> string.replace("\r", "\\r")
}
