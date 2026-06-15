import gleam/string

const separator = ": "

pub type Title {
  Title(base: String, group: String)
}

pub fn for_group(base base: String, group group: String) -> String {
  base <> separator <> group
}

pub fn split(title title: String) -> Title {
  case string.split_once(title, separator) {
    Ok(#(base, group)) -> Title(base:, group:)
    Error(Nil) -> Title(base: title, group: title)
  }
}
