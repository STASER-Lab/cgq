import gleam/option

import canvas

pub type Report {
  Report(message: String, hint: option.Option(String))
}

pub fn from_canvas(
  context context: String,
  error error: canvas.Error,
) -> Report {
  Report(
    message: context <> ". " <> canvas.error_summary(error),
    hint: canvas.error_hint(error),
  )
}
