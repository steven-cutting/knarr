import gleam/http
import gleam/http/request
import http_picture

pub fn a_request_without_a_body_is_its_request_line_and_headers_test() -> Nil {
  let request =
    request.new()
    |> request.set_host("example.invalid")
    |> request.set_path("/version")
    |> request.set_header("accept", "application/json")

  assert http_picture.request(request)
    == "GET https://example.invalid/version\naccept: application/json"
}

pub fn a_body_follows_one_blank_line_test() -> Nil {
  let request =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_host("example.invalid")
    |> request.set_path("/pods")
    |> request.set_header("content-type", "application/json")
    |> request.set_body("{\"kind\": \"Pod\"}")

  assert http_picture.request(request)
    == "POST https://example.invalid/pods\ncontent-type: application/json\n\n{\"kind\": \"Pod\"}"
}
