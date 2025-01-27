import gleam/int
import gleam/io
import gleam/list
import gleam/string

const vertical = "│"

const horizontal = "─"

const top_left = "┌"

const top_right = "┐"

const middle_left = "┤"

const middle_right = "├"

const middle_bottom = "┴"

const middle_top = "┬"

const bottom_left = "└"

const bottom_right = "┘"

const cross = "┼"

pub type Table(value) {
  Table(columns: List(Column(value)), rows: List(value))
}

pub type Column(value) {
  Column(header: String, align: Align, getter: fn(value) -> String)
}

pub type Align {
  Left
  Right
  Center
}

pub fn table(rows: List(value)) -> Table(value) {
  Table(columns: [], rows:)
}

pub fn param(f: fn(a) -> b) -> fn(a) -> b {
  f
}

pub fn with(
  builder: Table(value),
  header: String,
  align: Align,
  getter: fn(value) -> String,
) -> Table(value) {
  let Table(columns:, rows:) = builder
  Table(columns: [Column(header, align, getter), ..columns], rows:)
}

fn calculate_widths(headers: List(String), values: List(String)) -> List(Int) {
  let lengths = list.sized_chunk(values, list.length(headers))

  list.map2(headers, list.transpose(lengths), fn(header, col_values) {
    let max_value_length =
      list.fold(col_values, 0, fn(acc, val) { int.max(acc, string.length(val)) })
    int.max(string.length(header), max_value_length)
  })
}

pub fn print(table: Table(value)) -> Nil {
  let Table(columns:, rows:) = table
  let columns = list.reverse(columns)

  let headers = list.map(columns, fn(col) { col.header })
  let aligns = list.map(columns, fn(col) { col.align })
  let values =
    list.flat_map(rows, fn(row) {
      list.map(columns, fn(col) { col.getter(row) })
    })
  let widths = calculate_widths(headers, values)

  print_separator(widths, True, True)
  print_row(
    list.map(list.range(1, list.length(columns)), fn(_) { Center }),
    widths,
    headers,
  )
  print_separator(widths, True, False)

  list.each(rows, fn(row) {
    let row_values = list.map(columns, fn(col) { col.getter(row) })
    print_row(aligns, widths, row_values)
  })

  print_separator(widths, False, False)
}

fn print_separator(columns: List(Int), is_header: Bool, is_top: Bool) {
  let start = case is_top, is_header {
    True, _ -> top_left
    False, True -> middle_right
    False, False -> bottom_left
  }

  let end = case is_top, is_header {
    True, _ -> top_right
    False, True -> middle_left
    False, False -> bottom_right
  }

  let middle = case is_top, is_header {
    True, _ -> middle_top
    False, True -> cross
    False, False -> middle_bottom
  }

  let line =
    list.fold(columns, start, fn(acc, col) {
      acc <> string.repeat(horizontal, col + 2) <> middle
    })

  io.println(string.slice(line, 0, string.length(line) - 1) <> end)
}

fn print_row(aligns: List(Align), widths: List(Int), values: List(String)) {
  let row =
    {
      use #(align, width), value <- list.map2(
        {
          use align, width <- list.map2(aligns, widths)
          #(align, width)
        },
        values,
      )
      let padded = case align {
        Left -> pad_right(value, width)
        Right -> pad_left(value, width)
        Center -> pad_center(value, width)
      }
      " " <> padded <> " "
    }
    |> string.join(vertical)

  io.println(vertical <> row <> vertical)
}

fn pad_left(text: String, width: Int) {
  let padding = width - string.length(text)
  string.repeat(" ", padding) <> text
}

fn pad_right(text: String, width: Int) {
  let padding = width - string.length(text)
  text <> string.repeat(" ", padding)
}

fn pad_center(text: String, width: Int) {
  let padding = width - string.length(text)
  let left = padding / 2
  let right = padding - left
  string.repeat(" ", left) <> text <> string.repeat(" ", right)
}
