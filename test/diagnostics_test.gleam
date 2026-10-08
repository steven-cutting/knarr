import gleam/http
import gleam/http/request
import gleam/http/response
import gleeunit
import gleeunit/should
import knarr/diagnostics

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn health_test() -> Nil {
  let req = request.new() |> request.set_path("/healthz")
  let response = diagnostics.respond(req, False, fn() { "unused" })
  assert response.status == 200
  assert response.body == "ok\n"
}

pub fn readiness_test() -> Nil {
  let req = request.new() |> request.set_path("/readyz")
  assert diagnostics.respond(req, False, no_collection).status == 503
  assert diagnostics.respond(req, True, no_collection).status == 200
}

pub fn routing_test() -> Nil {
  let unknown = request.new() |> request.set_path("/other")
  assert diagnostics.respond(unknown, True, no_collection).status == 404
  let post =
    request.new()
    |> request.set_path("/healthz")
    |> request.set_method(http.Post)
  let response = diagnostics.respond(post, True, no_collection)
  assert response.status == 405
  assert response.get_header(response, "allow") == Ok("GET")
}

pub fn exposition_test() -> Nil {
  let req = request.new() |> request.set_path("/metrics")
  let result = diagnostics.respond(req, True, fn() { "counter 1\n" })
  assert result.status == 200
  assert result.body == "counter 1\n"
  assert response.get_header(result, "content-type")
    == Ok("text/plain; version=0.0.4; charset=utf-8")
}

fn no_collection() -> String {
  should.fail()
  ""
}
