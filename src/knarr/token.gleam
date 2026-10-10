//// The projected service-account token's expiry claim, read so a log line
//// can say when the token the process last loaded expires. Nothing here
//// verifies the token: the apiserver does that.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/result
import gleam/string

/// Why no expiry could be read.
pub type JwtError {
  NotThreeSegments
  NotBase64Url
  NotJsonClaims
  NoExpClaim
  ExpNotAnInteger
}

/// The `exp` claim of a JWT, in unix seconds. The claims segment is
/// base64url without padding, which the decoder pads itself.
pub fn jwt_expiry(token: String) -> Result(Int, JwtError) {
  case string.split(token, ".") {
    [_, claims, _] -> {
      use bytes <- result.try(
        bit_array.base64_url_decode(claims)
        |> result.replace_error(NotBase64Url),
      )
      use text <- result.try(
        bit_array.to_string(bytes) |> result.replace_error(NotJsonClaims),
      )
      json.parse(text, decode.field("exp", decode.int, decode.success))
      |> result.map_error(fn(error) {
        case error {
          json.UnableToDecode([decode.DecodeError(_, "Nothing", _)]) ->
            NoExpClaim
          json.UnableToDecode(_) -> ExpNotAnInteger
          _ -> NotJsonClaims
        }
      })
    }
    _ -> Error(NotThreeSegments)
  }
}
