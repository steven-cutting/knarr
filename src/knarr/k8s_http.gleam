//// The HTTPS adapter behind the k8s_client contract: `send` has the type
//// the client's `send` argument expects and carries every request over
//// verified TLS (VerifiedTls in docs/specs/k8s_client.allium). The only
//// Erlang here is `k8s_http_ffi`, which calls `httpc:request` with explicit
//// ssl options: verify_peer, the given CA file alone, and an https hostname
//// check that matches an IP-literal host against the IP subjectAltName.
//// There is no unverified path.

import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/uri

/// The CA the peer must chain to: in a pod, the service account's `ca.crt`.
pub type Tls {
  Tls(ca_file: String)
}

/// Why no response came back. Every value is safe to log: none carries the
/// request or its headers.
pub type SendError {
  /// The handshake failed with this TLS alert, such as `unknown_ca`.
  TlsAlert(String)
  /// No connection, such as `econnrefused`.
  ConnectFailed(String)
  Timeout
  Other(String)
}

/// Sends `request` over TLS verified against `tls`. httpc takes the content
/// type as its own argument, so it leaves the header list here; otherwise a
/// PATCH would carry two content-type headers.
pub fn send(
  request request: Request(String),
  tls tls: Tls,
) -> Result(Response(String), SendError) {
  let url = uri.to_string(request.to_uri(request))
  let #(content_type, headers) = case
    list.key_pop(request.headers, "content-type")
  {
    Ok(#(content_type, headers)) -> #(content_type, headers)
    Error(Nil) -> #("", request.headers)
  }
  case
    do_request(
      http.method_to_string(request.method),
      url,
      headers,
      content_type,
      request.body,
      tls.ca_file,
    )
  {
    Ok(#(status, headers, body)) ->
      Ok(response.Response(status:, headers:, body:))
    Error(error) -> Error(error)
  }
}

@external(erlang, "k8s_http_ffi", "request")
fn do_request(
  method: String,
  url: String,
  headers: List(#(String, String)),
  content_type: String,
  body: String,
  ca_file: String,
) -> Result(#(Int, List(#(String, String)), String), SendError)
