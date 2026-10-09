//// Tests for the k8s_client contract's builders, decoders and joins. The
//// builders and decoders are pure, so their tests pass values in and read
//// values out; `list_pods` and `patch_annotation` go through closure fakes.

import birdie
import gleam/dict
import gleam/http
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import http_picture
import knarr/k8s_client.{Pod, Target}
import qcheck

const target = Target(host: "10.96.0.1", port: 443)

// A kind apiserver's pod list, cut down: two pods, one terminating, one with
// no annotations map at all, and more fields than the decoder reads.
const pod_list_body =
  "{
  \"kind\": \"PodList\",
  \"apiVersion\": \"v1\",
  \"metadata\": {\"resourceVersion\": \"1234\"},
  \"items\": [
    {
      \"metadata\": {
        \"name\": \"knarr-7d4b9c-abcde\",
        \"namespace\": \"default\",
        \"uid\": \"6f1c\",
        \"annotations\": {\"knarr.io/s1-probe\": \"1760000000\"},
        \"labels\": {\"app.kubernetes.io/name\": \"knarr\"}
      },
      \"spec\": {\"nodeName\": \"kind-control-plane\"},
      \"status\": {\"phase\": \"Running\"}
    },
    {
      \"metadata\": {
        \"name\": \"knarr-7d4b9c-zzzzz\",
        \"namespace\": \"default\",
        \"deletionTimestamp\": \"2026-10-09T05:00:00Z\"
      },
      \"status\": {\"phase\": \"Running\"}
    }
  ]
}"

const patched_pod_body =
  "{
  \"kind\": \"Pod\",
  \"apiVersion\": \"v1\",
  \"metadata\": {
    \"name\": \"knarr-7d4b9c-abcde\",
    \"annotations\": {\"knarr.io/s1-probe\": \"1760000060\"}
  }
}"

const forbidden_body =
  "{\"kind\":\"Status\",\"status\":\"Failure\",\"message\":\"pods is forbidden\",\"reason\":\"Forbidden\",\"code\":403}"

pub fn list_pods_request_gets_the_namespace_pods_over_https_test() -> Nil {
  let request =
    k8s_client.list_pods_request(
      target:,
      namespace: "default",
      token: "test-token",
    )

  assert request.method == http.Get
  assert request.scheme == http.Https
  assert request.host == "10.96.0.1"
  assert request.port == Some(443)
  assert request.path == "/api/v1/namespaces/default/pods"
  assert request.query == None
  assert request.body == ""
}

pub fn list_pods_request_carries_the_bearer_token_and_accepts_json_test() -> Nil {
  let request =
    k8s_client.list_pods_request(
      target:,
      namespace: "default",
      token: "test-token",
    )

  assert request.headers
    == [
      #("accept", "application/json"),
      #("authorization", "Bearer test-token"),
    ]
}

pub fn patch_annotation_request_merge_patches_one_pod_test() -> Nil {
  let request =
    k8s_client.patch_annotation_request(
      target:,
      namespace: "default",
      pod: "knarr-7d4b9c-abcde",
      token: "test-token",
      key: "knarr.io/s1-probe",
      value: "1760000060",
    )

  assert request.method == http.Patch
  assert request.scheme == http.Https
  assert request.host == "10.96.0.1"
  assert request.port == Some(443)
  assert request.path == "/api/v1/namespaces/default/pods/knarr-7d4b9c-abcde"
  assert request.headers
    == [
      #("accept", "application/json"),
      #("authorization", "Bearer test-token"),
      #("content-type", "application/merge-patch+json"),
    ]
  assert request.body
    == "{\"metadata\":{\"annotations\":{\"knarr.io/s1-probe\":\"1760000060\"}}}"
}

pub fn decode_pod_list_reads_names_annotations_and_deletion_timestamps_test() -> Nil {
  let response = response.new(200) |> response.set_body(pod_list_body)

  assert k8s_client.decode_pod_list(response)
    == Ok([
      Pod(
        name: "knarr-7d4b9c-abcde",
        annotations: dict.from_list([#("knarr.io/s1-probe", "1760000000")]),
        deletion_timestamp: None,
      ),
      Pod(
        name: "knarr-7d4b9c-zzzzz",
        annotations: dict.new(),
        deletion_timestamp: Some("2026-10-09T05:00:00Z"),
      ),
    ])
}

pub fn decode_pod_list_keeps_the_body_of_any_status_but_200_test() -> Nil {
  let response = response.new(403) |> response.set_body(forbidden_body)

  assert k8s_client.decode_pod_list(response)
    == Error(k8s_client.UnexpectedStatus(403, forbidden_body))
}

pub fn decode_pod_list_reports_a_truncated_body_test() -> Nil {
  let response = response.new(200) |> response.set_body("{\"items\": [")

  assert k8s_client.decode_pod_list(response)
    == Error(k8s_client.UndecodableBody(json.UnexpectedEndOfInput))
}

pub fn decode_patched_pod_reads_the_pod_the_apiserver_returns_test() -> Nil {
  let response = response.new(200) |> response.set_body(patched_pod_body)

  assert k8s_client.decode_patched_pod(response)
    == Ok(Pod(
      name: "knarr-7d4b9c-abcde",
      annotations: dict.from_list([#("knarr.io/s1-probe", "1760000060")]),
      deletion_timestamp: None,
    ))
}

pub fn decode_patched_pod_keeps_the_body_of_any_status_but_200_test() -> Nil {
  let response = response.new(403) |> response.set_body(forbidden_body)

  assert k8s_client.decode_patched_pod(response)
    == Error(k8s_client.UnexpectedStatus(403, forbidden_body))
}

pub fn list_pods_sends_the_built_request_and_decodes_the_reply_test() -> Nil {
  let send = fn(request) {
    assert request
      == k8s_client.list_pods_request(
        target:,
        namespace: "default",
        token: "test-token",
      )
    Ok(response.new(200) |> response.set_body(pod_list_body))
  }

  let pods =
    k8s_client.list_pods(
      target:,
      namespace: "default",
      token: "test-token",
      send:,
    )
    |> should.be_ok
  assert list.map(pods, fn(pod) { pod.name })
    == ["knarr-7d4b9c-abcde", "knarr-7d4b9c-zzzzz"]
  assert list.map(pods, fn(pod) { pod.deletion_timestamp })
    == [None, Some("2026-10-09T05:00:00Z")]
}

pub fn list_pods_keeps_the_error_send_returned_test() -> Nil {
  let send = fn(_request) { Error("connection refused") }

  assert k8s_client.list_pods(
      target:,
      namespace: "default",
      token: "test-token",
      send:,
    )
    == Error(k8s_client.SendFailed("connection refused"))
}

pub fn patch_annotation_sends_the_built_request_and_decodes_the_reply_test() -> Nil {
  let send = fn(request) {
    assert request
      == k8s_client.patch_annotation_request(
        target:,
        namespace: "default",
        pod: "knarr-7d4b9c-abcde",
        token: "test-token",
        key: "knarr.io/s1-probe",
        value: "1760000060",
      )
    Ok(response.new(200) |> response.set_body(patched_pod_body))
  }

  let pod =
    k8s_client.patch_annotation(
      target:,
      namespace: "default",
      pod: "knarr-7d4b9c-abcde",
      token: "test-token",
      key: "knarr.io/s1-probe",
      value: "1760000060",
      send:,
    )
    |> should.be_ok
  assert dict.get(pod.annotations, "knarr.io/s1-probe") == Ok("1760000060")
}

pub fn patch_annotation_keeps_the_error_send_returned_test() -> Nil {
  let send = fn(_request) { Error("tls alert") }

  assert k8s_client.patch_annotation(
      target:,
      namespace: "default",
      pod: "knarr-7d4b9c-abcde",
      token: "test-token",
      key: "knarr.io/s1-probe",
      value: "1760000060",
      send:,
    )
    == Error(k8s_client.SendFailed("tls alert"))
}

// A property in the gate takes a fixed seed (docs/reference/testing.md).
// Any annotation key and value the builder encodes, the decoder reads back
// from a pod carrying it.
pub fn patched_annotation_reads_back_any_encoded_key_and_value_test() -> Nil {
  let config = qcheck.default_config() |> qcheck.with_seed(qcheck.seed(14))
  let annotations = qcheck.tuple2(qcheck.string(), qcheck.string())
  use #(key, value) <- qcheck.run(config, annotations)
  let request =
    k8s_client.patch_annotation_request(
      target:,
      namespace: "default",
      pod: "p",
      token: "test-token",
      key:,
      value:,
    )
  // The apiserver returns the merged pod; the patch body is its annotations.
  let body =
    "{\"metadata\":{\"name\":\"p\"," <> drop_metadata_wrapper(request.body)
  let response = response.new(200) |> response.set_body(body)

  assert k8s_client.decode_patched_pod(response)
    == Ok(Pod(
      name: "p",
      annotations: dict.from_list([#(key, value)]),
      deletion_timestamp: None,
    ))
}

// `{"metadata":{"annotations":{...}}}` becomes `"annotations":{...}}}`.
fn drop_metadata_wrapper(patch: String) -> String {
  let rest = string.split_once(patch, "{\"metadata\":{") |> should.be_ok
  rest.1
}

// Pictures are taken inside the fakes, so each is exactly the request the
// function handed to send. The named tests above are what prove them.
pub fn snapshot_list_pods_request_test() -> Nil {
  let send = fn(request) {
    http_picture.request(request)
    |> birdie.snap(title: "pod list request sent by list_pods")
    Ok(response.new(200) |> response.set_body(pod_list_body))
  }

  k8s_client.list_pods(
    target:,
    namespace: "default",
    token: "test-token",
    send:,
  )
  |> should.be_ok
  Nil
}

pub fn snapshot_patch_annotation_request_test() -> Nil {
  let send = fn(request) {
    http_picture.request(request)
    |> birdie.snap(title: "merge patch request sent by patch_annotation")
    Ok(response.new(200) |> response.set_body(patched_pod_body))
  }

  k8s_client.patch_annotation(
    target:,
    namespace: "default",
    pod: "knarr-7d4b9c-abcde",
    token: "test-token",
    key: "knarr.io/s1-probe",
    value: "1760000060",
    send:,
  )
  |> should.be_ok
  Nil
}
