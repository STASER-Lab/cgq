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

pub fn frame(
  rendered rendered: String,
  palette palette: questions.Palette,
) -> String {
  use tinted, character <- list.fold(box_characters, rendered)
  string.replace(tinted, character, palette.frame <> character <> palette.reset)
}
