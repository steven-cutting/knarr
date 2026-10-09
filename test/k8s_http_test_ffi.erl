-module(k8s_http_test_ffi).
-export([start_responder/0, stop_responder/1, closed_port/0, count_lines/2]).
-include_lib("public_key/include/public_key.hrl").

%% A loopback TLS responder. Its CA and leaf come from
%% public_key:pkix_test_data/1, in memory; only the CA PEMs are written, under
%% build/, so the client can be given a cacertfile. The leaf carries an
%% iPAddress subjectAltName for 127.0.0.1, which the https hostname check
%% matches a string IP host against.
start_responder() ->
  {ok, _} = application:ensure_all_started(ssl),
  {ok, _} = application:ensure_all_started(inets),
  Dir = filename:join(["build", "k8s_http_test", integer_to_list(erlang:unique_integer([positive]))]),
  ok = filelib:ensure_path(Dir),
  Server = chain(),
  Other = chain(),
  CaFile = write_ca(Dir, "ca.pem", Server),
  OtherCaFile = write_ca(Dir, "other-ca.pem", Other),
  {ok, Listen} = ssl:listen(0, [{ip, {127, 0, 0, 1}}, {reuseaddr, true}, {active, false}, binary,
                                {cert, proplists:get_value(cert, Server)},
                                {key, proplists:get_value(key, Server)}]),
  {ok, {_, Port}} = ssl:sockname(Listen),
  Acceptor = spawn(fun() -> accept(Listen) end),
  {responder, Port, unicode:characters_to_binary(CaFile), unicode:characters_to_binary(OtherCaFile), Acceptor}.

stop_responder({responder, _, _, _, Acceptor}) ->
  exit(Acceptor, kill),
  nil.

chain() ->
  San = #'Extension'{extnID = ?'id-ce-subjectAltName',
    extnValue = [{iPAddress, <<127, 0, 0, 1>>}], critical = false},
  public_key:pkix_test_data(#{root => [{key, {rsa, 2048, 65537}}], intermediates => [],
    peer => [{key, {rsa, 2048, 65537}}, {extensions, [San]}]}).

write_ca(Dir, Name, Conf) ->
  CaCerts = lists:usort(proplists:get_value(cacerts, Conf)),
  Path = filename:join(Dir, Name),
  ok = file:write_file(Path, public_key:pem_encode([{'Certificate', C, not_encrypted} || C <- CaCerts])),
  Path.

accept(Listen) ->
  case ssl:transport_accept(Listen) of
    {ok, Transport} -> spawn(fun() -> serve(Transport) end), accept(Listen);
    {error, _} -> ok
  end.

%% One request per connection. /echo answers with the request head it
%% received, one lower-cased "name: value" line per header; any other path
%% answers an empty pod list.
serve(Transport) ->
  case ssl:handshake(Transport, 5000) of
    {ok, Socket} ->
      ok = ssl:setopts(Socket, [{packet, http_bin}]),
      case read_head(Socket, undefined, []) of
        {ok, Path, Head} ->
          Body = case Path of
            <<"/echo">> -> Head;
            _ -> <<"{\"kind\":\"PodList\",\"items\":[]}">>
          end,
          ok = ssl:send(Socket, [<<"HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: ">>,
            integer_to_binary(byte_size(Body)), <<"\r\nconnection: close\r\n\r\n">>, Body]);
        error -> ok
      end,
      ssl:close(Socket);
    {error, _} -> ok
  end.

read_head(Socket, Path, Lines) ->
  case ssl:recv(Socket, 0, 2000) of
    {ok, {http_request, _, {abs_path, RequestPath}, _}} -> read_head(Socket, RequestPath, Lines);
    {ok, {http_header, _, Name, _, Value}} ->
      Line = <<(string:lowercase(name(Name)))/binary, ": ", Value/binary>>,
      read_head(Socket, Path, [Line | Lines]);
    {ok, http_eoh} -> {ok, Path, iolist_to_binary(lists:join(<<"\n">>, lists:reverse(Lines)))};
    _ -> error
  end.

name(Name) when is_atom(Name) -> atom_to_binary(Name);
name(Name) -> Name.

closed_port() ->
  {ok, Socket} = gen_tcp:listen(0, [{ip, {127, 0, 0, 1}}]),
  {ok, {_, Port}} = inet:sockname(Socket),
  gen_tcp:close(Socket),
  Port.

count_lines(Text, Line) ->
  length([L || L <- string:split(Text, <<"\n">>, all), L =:= Line]).
