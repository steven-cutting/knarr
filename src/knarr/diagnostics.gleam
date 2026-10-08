//// Routing takes values only; respond is the adapter for injected collection.

import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}

type Body {
  Text(String)
  Metrics
}

pub fn respond(
  request: Request(body),
  ready: Bool,
  collect: fn() -> String,
) -> Response(String) {
  let decision = route(request, ready)
  let body = case decision.body {
    Text(body) -> body
    Metrics -> collect()
  }
  response.set_body(decision, body)
}

fn route(request: Request(body), ready: Bool) -> Response(Body) {
  case request.path {
    "/healthz" | "/readyz" | "/metrics" ->
      case request.method {
        http.Get ->
          case request.path, ready {
            "/readyz", False ->
              response.new(503) |> response.set_body(Text("starting\n"))
            "/metrics", _ ->
              response.new(200)
              |> response.set_header(
                "content-type",
                "text/plain; version=0.0.4; charset=utf-8",
              )
              |> response.set_body(Metrics)
            _, _ -> response.new(200) |> response.set_body(Text("ok\n"))
          }
        _ ->
          response.new(405)
          |> response.set_header("allow", "GET")
          |> response.set_body(Text("method not allowed\n"))
      }
    _ -> response.new(404) |> response.set_body(Text("not found\n"))
  }
}
