//// The k8s_client contract (docs/specs/k8s_client.allium): pure request
//// builders and response decoders for the two verbs spike S1 proved, list
//// and patch on pods, joined by functions that do I/O only through the
//// `send` they are given (Decision 0002). Production passes
//// `k8s_http.send` with the service-account CA; a test passes a closure.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option}
import gleam/result

/// The apiserver, as `KUBERNETES_SERVICE_HOST` and `_PORT` name it.
pub type Target {
  Target(host: String, port: Int)
}

/// What the client reads of a pod: its name, its annotations (an absent map
/// is empty) and whether it is terminating.
pub type Pod {
  Pod(
    name: String,
    annotations: Dict(String, String),
    deletion_timestamp: Option(String),
  )
}

/// Why a call returned no value. `e` is the error type of the `send` it was
/// given. A status other than 200 keeps its body: a 403 carries the reason
/// RBAC refused the verb.
pub type ClientError(e) {
  SendFailed(e)
  UnexpectedStatus(status: Int, body: String)
  UndecodableBody(json.DecodeError)
}

/// `GET /api/v1/namespaces/{namespace}/pods`, as the bearer of `token`.
pub fn list_pods_request(
  target target: Target,
  namespace namespace: String,
  token token: String,
) -> Request(String) {
  base_request(target:, token:)
  |> request.set_method(http.Get)
  |> request.set_path("/api/v1/namespaces/" <> namespace <> "/pods")
}

/// `PATCH /api/v1/namespaces/{namespace}/pods/{pod}` with a merge patch that
/// sets one annotation and touches nothing else.
pub fn patch_annotation_request(
  target target: Target,
  namespace namespace: String,
  pod pod: String,
  token token: String,
  key key: String,
  value value: String,
) -> Request(String) {
  let body =
    json.object([
      #(
        "metadata",
        json.object([
          #("annotations", json.object([#(key, json.string(value))])),
        ]),
      ),
    ])
  base_request(target:, token:)
  |> request.set_method(http.Patch)
  |> request.set_path("/api/v1/namespaces/" <> namespace <> "/pods/" <> pod)
  |> request.set_header("content-type", "application/merge-patch+json")
  |> request.set_body(json.to_string(body))
}

fn base_request(target target: Target, token token: String) -> Request(String) {
  request.new()
  |> request.set_scheme(http.Https)
  |> request.set_host(target.host)
  |> request.set_port(target.port)
  |> request.set_header("accept", "application/json")
  |> request.set_header("authorization", "Bearer " <> token)
}

/// Reads the pods from a list reply. Only a 200 carries one.
pub fn decode_pod_list(
  response: Response(String),
) -> Result(List(Pod), ClientError(e)) {
  decode_200(
    response,
    decode.field("items", decode.list(pod_decoder()), decode.success),
  )
}

/// Reads the pod a patch reply returns. Only a 200 carries one.
pub fn decode_patched_pod(
  response: Response(String),
) -> Result(Pod, ClientError(e)) {
  decode_200(response, pod_decoder())
}

fn decode_200(
  response: Response(String),
  decoder: decode.Decoder(a),
) -> Result(a, ClientError(e)) {
  case response.status {
    200 ->
      json.parse(response.body, decoder) |> result.map_error(UndecodableBody)
    status -> Error(UnexpectedStatus(status, response.body))
  }
}

fn pod_decoder() -> decode.Decoder(Pod) {
  use pod <- decode.field("metadata", metadata_decoder())
  decode.success(pod)
}

fn metadata_decoder() -> decode.Decoder(Pod) {
  use name <- decode.field("name", decode.string)
  use annotations <- decode.optional_field(
    "annotations",
    dict.new(),
    decode.dict(decode.string, decode.string),
  )
  use deletion_timestamp <- decode.optional_field(
    "deletionTimestamp",
    option.None,
    decode.optional(decode.string),
  )
  decode.success(Pod(name:, annotations:, deletion_timestamp:))
}

/// Lists the pods in `namespace`. The only I/O is the call to `send`.
pub fn list_pods(
  target target: Target,
  namespace namespace: String,
  token token: String,
  send send: fn(Request(String)) -> Result(Response(String), e),
) -> Result(List(Pod), ClientError(e)) {
  use response <- result.try(
    list_pods_request(target:, namespace:, token:)
    |> send
    |> result.map_error(SendFailed),
  )
  decode_pod_list(response)
}

/// Sets one annotation on `pod` with a merge patch and returns the pod the
/// apiserver sends back. The only I/O is the call to `send`.
pub fn patch_annotation(
  target target: Target,
  namespace namespace: String,
  pod pod: String,
  token token: String,
  key key: String,
  value value: String,
  send send: fn(Request(String)) -> Result(Response(String), e),
) -> Result(Pod, ClientError(e)) {
  use response <- result.try(
    patch_annotation_request(target:, namespace:, pod:, token:, key:, value:)
    |> send
    |> result.map_error(SendFailed),
  )
  decode_patched_pod(response)
}
