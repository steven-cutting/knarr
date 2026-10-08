//// A worked example of Decision 0002's sans-IO pattern, kept in test/ because
//// it is not part of knarr. It reads the Kubernetes apiserver's `GET /version`,
//// a real, read-only call that decides nothing, in three parts:
////
//// - `version_request` builds the request and performs no I/O.
//// - `decode_version` reads a response and performs no I/O.
//// - `fetch_version` joins them, and does I/O only through the `send` it is
////   given.
////
//// `send` has the type of `gleam_httpc.send`, so production code passes
//// `httpc.send` unchanged and a test passes a closure. docs/reference/testing.md
//// walks through it.

import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/result

/// The apiserver's version. Kubernetes sends every field as a string, and a
/// managed cluster's `minor` may carry a suffix, such as `"35+"`.
pub type Version {
  Version(major: String, minor: String, git_version: String)
}

/// Why `fetch_version` returned no version. `e` is the error type of the
/// `send` it was given.
pub type FetchError(e) {
  SendFailed(e)
  UnexpectedStatus(Int)
  UndecodableBody(json.DecodeError)
}

/// The request for the apiserver's version, on `host`.
pub fn version_request(host: String) -> Request(String) {
  request.new()
  |> request.set_scheme(http.Https)
  |> request.set_method(http.Get)
  |> request.set_host(host)
  |> request.set_path("/version")
  |> request.set_header("accept", "application/json")
}

/// Reads the version from the apiserver's response. Only a 200 carries one.
pub fn decode_version(
  response: Response(String),
) -> Result(Version, FetchError(e)) {
  case response.status {
    200 ->
      json.parse(response.body, version_decoder())
      |> result.map_error(UndecodableBody)
    status -> Error(UnexpectedStatus(status))
  }
}

fn version_decoder() -> decode.Decoder(Version) {
  use major <- decode.field("major", decode.string)
  use minor <- decode.field("minor", decode.string)
  use git_version <- decode.field("gitVersion", decode.string)
  decode.success(Version(major:, minor:, git_version:))
}

/// Asks the apiserver on `host` for its version. The only I/O is the call to
/// `send`.
pub fn fetch_version(
  host: String,
  send: fn(Request(String)) -> Result(Response(String), e),
) -> Result(Version, FetchError(e)) {
  use response <- result.try(
    version_request(host)
    |> send
    |> result.map_error(SendFailed),
  )
  decode_version(response)
}
