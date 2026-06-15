import gleam/list
import gleam/string

import gleeunit/should
import simplifile

import cgq/questions

const fixtures_directory = "test/fixtures"

// Each test/fixtures/<name>.toml is an intentionally broken template paired with
// a <name>.expected snapshot of its rendered diagnostic. Read the .expected
// files to see how every error category renders; this test keeps them honest.
// To refresh after a deliberate rendering change: regenerate the snapshots and
// review the diff.
pub fn fixtures_render_expected_diagnostics_test() {
  let fixtures = fixture_paths()

  { fixtures != [] }
  |> should.be_true

  use #(toml_path, expected_path) <- list.each(fixtures)

  let rendered = case
    questions.load(filepath: toml_path, palette: questions.no_color())
  {
    Ok(_) ->
      panic as { toml_path <> " parsed cleanly but is meant to be invalid" }
    Error(rendered) -> rendered
  }

  let assert Ok(expected) = simplifile.read(expected_path)

  rendered
  |> should.equal(string.trim_end(expected))
}

fn fixture_paths() -> List(#(String, String)) {
  let assert Ok(names) = simplifile.read_directory(at: fixtures_directory)

  names
  |> list.filter(string.ends_with(_, ".toml"))
  |> list.sort(string.compare)
  |> list.map(fn(name) {
    let base = string.drop_end(name, string.length(".toml"))
    #(
      fixtures_directory <> "/" <> name,
      fixtures_directory <> "/" <> base <> ".expected",
    )
  })
}
