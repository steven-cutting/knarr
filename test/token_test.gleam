//// Tests for the projected token's expiry claim. Each token is assembled
//// here from its parts, so no literal JWT is in the repository.

import gleam/bit_array
import gleam/json
import knarr/token

fn segment(value: json.Json) -> String {
  json.to_string(value)
  |> bit_array.from_string
  |> bit_array.base64_url_encode(False)
}

fn jwt(claims: json.Json) -> String {
  let header = json.object([#("alg", json.string("RS256"))])
  segment(header) <> "." <> segment(claims) <> ".signature-not-checked"
}

pub fn jwt_expiry_reads_the_exp_claim_test() -> Nil {
  let claims =
    json.object([
      #("iss", json.string("https://kubernetes.default.svc")),
      #("exp", json.int(1_760_000_600)),
      #("iat", json.int(1_760_000_000)),
    ])

  assert token.jwt_expiry(jwt(claims)) == Ok(1_760_000_600)
}

pub fn jwt_expiry_pads_an_unpadded_segment_test() -> Nil {
  // {"exp":1} encodes to 11 characters, which base64url leaves unpadded.
  let claims = json.object([#("exp", json.int(1))])

  assert token.jwt_expiry(jwt(claims)) == Ok(1)
}

pub fn jwt_expiry_needs_three_segments_test() -> Nil {
  assert token.jwt_expiry("one.two") == Error(token.NotThreeSegments)
}

pub fn jwt_expiry_reports_a_segment_that_is_not_base64url_test() -> Nil {
  assert token.jwt_expiry("a.%%%.c") == Error(token.NotBase64Url)
}

pub fn jwt_expiry_reports_claims_without_exp_test() -> Nil {
  let claims = json.object([#("iat", json.int(1_760_000_000))])

  assert token.jwt_expiry(jwt(claims)) == Error(token.NoExpClaim)
}

pub fn jwt_expiry_reports_an_exp_that_is_not_an_integer_test() -> Nil {
  let claims = json.object([#("exp", json.string("later"))])

  assert token.jwt_expiry(jwt(claims)) == Error(token.ExpNotAnInteger)
}
