import gleam/dynamic/decode

pub type User {
  User(id: Int, name: String)
}

pub fn decoder() -> decode.Decoder(User) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  decode.success(User(id:, name:))
}
