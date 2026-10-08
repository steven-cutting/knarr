//// Tests for the worked sans-IO example (docs/reference/testing.md). The
//// builder and the decoder are pure, so their tests pass values in and read
//// values out; `fetch_version` is exercised through a closure fake for `send`.

import birdie
import gleam/dynamic/decode
import gleam/http
import gleam/http/response
import gleam/json
import gleam/option.{None}
import http_picture
import qcheck
import sans_io_example.{type Version, Version}

// A kind v1.35.8 apiserver's /version reply, cut down to a few fields: every
// field is a string, and there are more fields than the decoder reads.
const kind_version_body =
  "{
  \"major\": \"1\",
  \"minor\": \"35\",
  \"gitVersion\": \"v1.35.8\",
  \"gitTreeState\": \"clean\",
  \"platform\": \"linux/arm64\"
}"

pub fn version_request_gets_slash_version_over_https_test() -> Nil {
  let request = sans_io_example.version_request("kind-control-plane")

  assert request.method == http.Get
  assert request.scheme == http.Https
  assert request.host == "kind-control-plane"
  assert request.port == None
  assert request.path == "/version"
  assert request.query == None
  assert request.body == ""
}

pub fn version_request_accepts_only_json_test() -> Nil {
  let request = sans_io_example.version_request("kind-control-plane")

  assert request.headers == [#("accept", "application/json")]
}

pub fn decode_version_reads_a_200_body_test() -> Nil {
  let response = response.new(200) |> response.set_body(kind_version_body)

  assert sans_io_example.decode_version(response)
    == Ok(Version(major: "1", minor: "35", git_version: "v1.35.8"))
}

pub fn decode_version_refuses_any_status_but_200_test() -> Nil {
  // The body would decode; the status alone makes this an error.
  let response = response.new(503) |> response.set_body(kind_version_body)

  assert sans_io_example.decode_version(response)
    == Error(sans_io_example.UnexpectedStatus(503))
}

pub fn decode_version_reports_a_truncated_body_test() -> Nil {
  let response = response.new(200) |> response.set_body("{\"major\": \"1\"")

  assert sans_io_example.decode_version(response)
    == Error(sans_io_example.UndecodableBody(json.UnexpectedEndOfInput))
}

pub fn decode_version_reports_a_field_of_the_wrong_type_test() -> Nil {
  let body = "{\"major\": 1, \"minor\": \"35\", \"gitVersion\": \"v1.35.8\"}"
  let response = response.new(200) |> response.set_body(body)

  assert sans_io_example.decode_version(response)
    == Error(
      sans_io_example.UndecodableBody(
        json.UnableToDecode([
          decode.DecodeError(expected: "String", found: "Int", path: ["major"]),
        ]),
      ),
    )
}

pub fn fetch_version_sends_the_built_request_and_decodes_the_reply_test() -> Nil {
  let send = fn(request) {
    assert request == sans_io_example.version_request("kind-control-plane")
    Ok(response.new(200) |> response.set_body(kind_version_body))
  }

  assert sans_io_example.fetch_version("kind-control-plane", send)
    == Ok(Version(major: "1", minor: "35", git_version: "v1.35.8"))
}

pub fn fetch_version_keeps_the_error_send_returned_test() -> Nil {
  let send = fn(_request) { Error("connection refused") }

  assert sans_io_example.fetch_version("kind-control-plane", send)
    == Error(sans_io_example.SendFailed("connection refused"))
}

// A property in the gate takes a fixed seed. qcheck prints the failing and the
// shrunk value but never the seed, so a failure under a random one could not
// be replayed.
pub fn decode_version_reads_back_any_encoded_version_test() -> Nil {
  let config = qcheck.default_config() |> qcheck.with_seed(qcheck.seed(8))
  let versions =
    qcheck.map3(qcheck.string(), qcheck.string(), qcheck.string(), Version)
  use version <- qcheck.run(config, versions)
  let response = response.new(200) |> response.set_body(encode(version))

  assert sans_io_example.decode_version(response) == Ok(version)
}

fn encode(version: Version) -> String {
  json.object([
    #("major", json.string(version.major)),
    #("minor", json.string(version.minor)),
    #("gitVersion", json.string(version.git_version)),
  ])
  |> json.to_string
}

// The picture is taken inside the fake, so it is exactly the request
// fetch_version handed to send. It is for a reviewer to read; the named tests
// above are what prove the request.
pub fn snapshot_version_request_test() -> Nil {
  let send = fn(request) {
    http_picture.request(request)
    |> birdie.snap(title: "version request sent by fetch_version")
    Ok(response.new(200) |> response.set_body(kind_version_body))
  }

  assert sans_io_example.fetch_version("kind-control-plane", send)
    == Ok(Version(major: "1", minor: "35", git_version: "v1.35.8"))
}
