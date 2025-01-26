import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/string

import birl

pub type Form {
  Form(values: dict.Dict(String, FormValue))
}

pub type FormValue {
  Bool(String)
  Int(String)
  String(String)
  Object(List(#(String, FormValue)))
  List(List(FormValue))
  Null
}

pub type Encoder(a) =
  fn(a) -> FormValue

pub fn new() -> Form {
  Form(dict.new())
}

pub fn add(form: Form, key: String, value: FormValue) {
  let values = {
    use _ <- dict.upsert(in: form.values, update: key)

    value
  }

  Form(values:)
}

pub fn parameter(f: fn(a) -> b) -> fn(a) -> b {
  f
}

pub fn bool(input: Bool) -> FormValue {
  input |> bool.to_string |> Bool
}

pub fn int(input: Int) -> FormValue {
  input |> int.to_string |> Int
}

pub fn string(input: String) -> FormValue {
  input |> String
}

pub fn optional(from input: option.Option(a), of inner_type: fn(a) -> FormValue) {
  case input {
    option.Some(value) -> value |> inner_type
    option.None -> Null
  }
}

pub fn object(
  from input: a,
  of inner_type: fn(a) -> List(#(String, FormValue)),
) -> FormValue {
  input |> inner_type |> Object
}

pub fn list(
  from inputs: List(a),
  of inner_type: fn(a) -> FormValue,
) -> FormValue {
  list.map(inputs, inner_type) |> List
}

pub fn time(input: birl.Time) -> FormValue {
  input |> birl.to_iso8601 |> String
}

pub fn to_string(form form: Form) -> String {
  form.values
  |> dict.map_values(do_to_string)
  |> dict.values
  |> string.join("&")
  |> string.replace(each: " ", with: "%20")
  |> string.replace(each: ":", with: "%3A")
  |> string.replace(each: "\n", with: "%0A")
}

fn do_to_string(key: String, value: FormValue) -> String {
  case value {
    Bool(value) | Int(value) | String(value) -> key <> "=" <> value
    List(values) ->
      list.map(values, do_to_string(key, _))
      |> string.join("&")
    Object(entries) ->
      {
        use #(inner_key, value) <- list.map(entries)
        let key = key <> "[" <> inner_key <> "]"
        value |> do_to_string(key, _)
      }
      |> string.join("&")
    Null -> ""
  }
}
