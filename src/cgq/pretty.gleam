import gleam/io
import gleam/list
import gleam/string

import cgq/questions

pub fn progress(
  message message: String,
  palette palette: questions.Palette,
) -> Nil {
  io.println(palette.frame <> message <> palette.reset)
}

pub fn success(
  message message: String,
  palette palette: questions.Palette,
) -> Nil {
  io.println(palette.add <> "✓ " <> message <> palette.reset)
}

const box_characters = [
  "│", "─", "╭", "╮", "╰", "╯", "┌", "┐", "└", "┘", "┬", "┴", "├", "┤", "┼",
]

/// Tints a rendered table's borders with the frame colour. The table is already
/// laid out, so wrapping the box characters in colour codes cannot disturb the
/// column widths the way colouring cells would.
pub fn frame(
  rendered rendered: String,
  palette palette: questions.Palette,
) -> String {
  use tinted, character <- list.fold(box_characters, rendered)
  string.replace(tinted, character, palette.frame <> character <> palette.reset)
}
