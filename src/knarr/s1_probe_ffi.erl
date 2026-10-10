-module(s1_probe_ffi).
-export([read_file/1, sha256_hex12/1, unix_seconds/0, log_notice/1]).

read_file(Path) ->
  case file:read_file(Path) of
    {ok, Content} -> {ok, Content};
    {error, Reason} -> {error, {read_failed, atom_to_binary(Reason)}}
  end.

%% The first twelve hex characters of sha256: enough to see a change in a
%% log line, never enough to reconstruct the input.
sha256_hex12(Data) ->
  binary:part(binary:encode_hex(crypto:hash(sha256, Data), lowercase), 0, 12).

unix_seconds() -> erlang:system_time(second).

log_notice(Line) ->
  logger:notice("~s", [Line]),
  nil.
