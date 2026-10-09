//// The TLS transport against a loopback responder whose CA and server
//// certificate are built in memory (`public_key:pkix_test_data/1`), so no key
//// is committed. The server certificate carries an IP subjectAltName for
//// 127.0.0.1, and the client connects to the string "127.0.0.1", the form
//// KUBERNETES_SERVICE_HOST takes.

import gleam/erlang/process.{type Pid}
import gleam/http
import gleam/http/request
import gleam/http/response
import gleeunit/should
import knarr/k8s_http.{Tls}

/// A loopback TLS responder: its port, the file holding its CA and the file
/// holding an unrelated CA.
pub type Responder {
  Responder(port: Int, ca_file: String, other_ca_file: String, acceptor: Pid)
}

@external(erlang, "k8s_http_test_ffi", "start_responder")
fn start_responder() -> Responder

@external(erlang, "k8s_http_test_ffi", "stop_responder")
fn stop_responder(responder: Responder) -> Nil

@external(erlang, "k8s_http_test_ffi", "closed_port")
fn closed_port() -> Int

fn get(port: Int) -> request.Request(String) {
  request.new()
  |> request.set_scheme(http.Https)
  |> request.set_host("127.0.0.1")
  |> request.set_port(port)
  |> request.set_path("/api/v1/namespaces/default/pods")
  |> request.set_header("accept", "application/json")
}

pub fn send_completes_a_verified_handshake_with_the_right_ca_test() -> Nil {
  let responder = start_responder()
  let response =
    get(responder.port) |> k8s_http.send(Tls(responder.ca_file)) |> should.be_ok
  stop_responder(responder)

  assert response.status == 200
  assert response.body == "{\"kind\":\"PodList\",\"items\":[]}"
  assert response.get_header(response, "content-type") == Ok("application/json")
}

pub fn send_refuses_a_wrong_ca_with_no_fallback_test() -> Nil {
  let responder = start_responder()
  let result =
    get(responder.port) |> k8s_http.send(Tls(responder.other_ca_file))
  stop_responder(responder)

  assert result == Error(k8s_http.TlsAlert("unknown_ca"))
}

pub fn send_reports_a_closed_port_test() -> Nil {
  let responder = start_responder()
  let result = get(closed_port()) |> k8s_http.send(Tls(responder.ca_file))
  stop_responder(responder)

  assert result == Error(k8s_http.ConnectFailed("econnrefused"))
}

pub fn send_passes_content_type_as_httpc_own_argument_test() -> Nil {
  // The responder echoes the request head it received in its body, so the
  // test can count content-type lines: httpc takes the content type as its
  // own argument, and a PATCH must not carry the header twice.
  let responder = start_responder()
  let response =
    get(responder.port)
    |> request.set_method(http.Patch)
    |> request.set_path("/echo")
    |> request.set_header("content-type", "application/merge-patch+json")
    |> request.set_body("{}")
    |> k8s_http.send(Tls(responder.ca_file))
    |> should.be_ok
  stop_responder(responder)

  assert response.status == 200
  assert count_lines(
      response.body,
      "content-type: application/merge-patch+json",
    )
    == 1
  assert count_lines(response.body, "accept: application/json") == 1
}

@external(erlang, "k8s_http_test_ffi", "count_lines")
fn count_lines(text: String, line: String) -> Int

pub fn send_reports_a_method_httpc_does_not_take_as_a_value_test() -> Nil {
  let responder = start_responder()
  let result =
    get(responder.port)
    |> request.set_method(http.Other("PROPFIND"))
    |> k8s_http.send(Tls(responder.ca_file))
  stop_responder(responder)

  assert result
    == Error(k8s_http.Other("{unsupported_method,<<\"PROPFIND\">>}"))
}

pub fn send_refuses_a_body_without_a_content_type_as_a_value_test() -> Nil {
  let responder = start_responder()
  let result =
    get(responder.port)
    |> request.set_method(http.Post)
    |> request.set_body("{}")
    |> k8s_http.send(Tls(responder.ca_file))
  stop_responder(responder)

  assert result == Error(k8s_http.Other("body without content-type"))
}
