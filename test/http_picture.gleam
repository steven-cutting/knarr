//// Renders HTTP values as text for snapshot tests (docs/reference/testing.md).
//// The renderer adds no trailing whitespace and no trailing newline; birdie
//// adds the one newline its files end with. It strips nothing either, so a
//// snapshot's input should hold no value that ends in whitespace.

import gleam/http
import gleam/http/request.{type Request}
import gleam/list
import gleam/string
import gleam/uri

/// The method and URL, then each header in the order the request holds them,
/// then, if there is a body, one blank line and the body.
pub fn request(request: Request(String)) -> String {
  let request_line =
    http.method_to_string(request.method)
    <> " "
    <> uri.to_string(request.to_uri(request))
  let headers =
    list.map(request.headers, fn(header) { header.0 <> ": " <> header.1 })
  let head = string.join([request_line, ..headers], "\n")
  case request.body {
    "" -> head
    body -> head <> "\n\n" <> body
  }
}
