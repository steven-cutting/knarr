#!/usr/bin/env escript
%% Ticket 14 evidence: the client connects to the string "127.0.0.1" (what
%% KUBERNETES_SERVICE_HOST gives), not an IP tuple as 01 tested. Cases:
%%   ssl:connect with a string IP: ok on the IP-SAN cert, unknown_ca against
%%     ca-b, hostname_check_failed against the DNS-only cert; the listener's
%%     sni_fun records what SNI arrives.
%%   httpc:request over the same ssl options: a 200 round trip, the raw
%%     request the server received, and the full error terms for a wrong CA
%%     and a closed port, which shape the FFI's error mapping.
%%   public_key:pkix_test_data/1 with an iPAddress SAN on the peer: the chain
%%     the in-gate loopback test builds without a committed key.
%% Usage: escript tls_check.escript <cert-dir>   (exit 0 only if every case matches)
-mode(compile).
-include_lib("public_key/include/public_key.hrl").

main([Dir]) ->
    ok = logger:set_primary_config(level, warning),
    {ok, _} = application:ensure_all_started(ssl),
    {ok, _} = application:ensure_all_started(inets),
    io:format("otp_release ~s, erts ~s~n",
              [erlang:system_info(otp_release), erlang:system_info(version)]),
    io:format("crypto:info_lib() ~p~n", [crypto:info_lib()]),
    ets:new(sni, [named_table, public, bag]),
    ets:new(raw, [named_table, public, bag]),
    F = fun(Name) -> filename:join(Dir, Name) end,
    Full = listen([{certfile, F("server.pem")}, {keyfile, F("server.key")}]),
    DnsOnly = listen([{certfile, F("server-dns.pem")}, {keyfile, F("server-dns.key")}]),
    CaA = F("ca-a.pem"),
    CaB = F("ca-b.pem"),
    Closed = closed_port(),
    SslCases =
        [{"ssl string IP, right CA (IP SAN)", "127.0.0.1", Full, CaA, ok},
         {"ssl string IP, wrong CA (ca-b)", "127.0.0.1", Full, CaB, unknown_ca},
         {"ssl string IP, cert has no IP SAN", "127.0.0.1", DnsOnly, CaA, hostname}],
    R1 = [ssl_case(C) || C <- SslCases],
    io:format("sni_fun calls recorded for the ssl cases: ~p~n", [ets:tab2list(sni)]),
    ets:delete_all_objects(sni),
    HttpcCases =
        [{"httpc GET string IP, right CA", Full, CaA, ok},
         {"httpc GET string IP, wrong CA (ca-b)", Full, CaB, unknown_ca},
         {"httpc GET string IP, closed port", Closed, CaA, econnrefused}],
    R2 = [httpc_case(C) || C <- HttpcCases],
    io:format("sni_fun calls recorded for the httpc cases: ~p~n", [ets:tab2list(sni)]),
    R3 = [patch_case(Full, CaA)],
    R4 = [test_data_case(Dir)],
    Results = R1 ++ R2 ++ R3 ++ R4,
    case lists:all(fun(R) -> R end, Results) of
        true -> io:format("tls_check: all ~b cases matched~n", [length(Results)]), halt(0);
        false -> io:format("tls_check: MISMATCH~n"), halt(1)
    end;
main(_) ->
    io:format("usage: tls_check.escript <cert-dir>~n"),
    halt(2).

opts(Ca) ->
    [{verify, verify_peer}, {cacertfile, Ca},
     {customize_hostname_check, [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}].

listen(CertOpts) ->
    {ok, L} = ssl:listen(0, [{ip, {127, 0, 0, 1}}, {reuseaddr, true}, {active, false},
                             binary, {sni_fun, fun(Host) -> ets:insert(sni, {sni, Host}), [] end}
                             | CertOpts]),
    {ok, {_, Port}} = ssl:sockname(L),
    spawn_link(fun() -> accept(L) end),
    Port.

accept(L) ->
    {ok, T} = ssl:transport_accept(L),
    spawn(fun() -> serve(T) end),
    accept(L).

%% After the handshake, answer one HTTP request with a fixed 200 and record
%% the raw request bytes.
serve(T) ->
    case ssl:handshake(T, 5000) of
        {ok, S} ->
            case ssl:recv(S, 0, 2000) of
                {ok, Raw} ->
                    ets:insert(raw, {raw, Raw}),
                    Body = <<"{\"ok\":true}">>,
                    ok = ssl:send(S, [<<"HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: ">>,
                                      integer_to_binary(byte_size(Body)), <<"\r\nconnection: close\r\n\r\n">>, Body]);
                _ -> ok
            end,
            ssl:close(S);
        _ -> ok
    end.

closed_port() ->
    {ok, L} = gen_tcp:listen(0, [{ip, {127, 0, 0, 1}}]),
    {ok, {_, Port}} = inet:sockname(L),
    gen_tcp:close(L),
    Port.

ssl_case({Label, Host, Port, Ca, Want}) ->
    Got = case ssl:connect(Host, Port, [{active, false} | opts(Ca)], 5000) of
              {ok, S} ->
                  {ok, Info} = ssl:connection_information(S, [protocol, sni_hostname]),
                  ssl:close(S),
                  {ok, Info};
              {error, E} -> {error, E}
          end,
    report(Label, Want, Got, matches(Want, Got)).

httpc_case({Label, Port, Ca, Want}) ->
    Url = "https://127.0.0.1:" ++ integer_to_list(Port) ++ "/",
    Got = httpc:request(get, {Url, [{"accept", "application/json"}]},
                        [{ssl, opts(Ca)}, {timeout, 5000}, {connect_timeout, 5000}],
                        [{body_format, binary}]),
    report(Label, Want, Got, matches(Want, Got)).

%% The FFI passes content-type as httpc's own argument; this shows the header
%% set the server then receives, so the request carries it exactly once.
patch_case(Port, Ca) ->
    ets:delete_all_objects(raw),
    Url = "https://127.0.0.1:" ++ integer_to_list(Port) ++ "/api/v1/namespaces/default/pods/p",
    Got = httpc:request(patch, {Url, [{"authorization", "Bearer redacted"}, {"accept", "application/json"}],
                                "application/merge-patch+json", <<"{\"metadata\":{\"annotations\":{\"k\":\"v\"}}}">>},
                        [{ssl, opts(Ca)}, {timeout, 5000}, {connect_timeout, 5000}],
                        [{body_format, binary}]),
    [{raw, Raw}] = ets:tab2list(raw),
    io:format("raw PATCH request as received by the server:~n~s~n", [Raw]),
    ContentTypes = length([L || L <- string:split(Raw, "\r\n", all),
                                string:prefix(string:lowercase(L), "content-type:") =/= nomatch]),
    io:format("content-type header lines received: ~b~n", [ContentTypes]),
    report("httpc PATCH string IP, one content-type header", ok, Got,
           matches(ok, Got) andalso ContentTypes =:= 1).

%% The in-gate loopback test needs a CA and a leaf with an IP SAN built in
%% memory. Build them with pkix_test_data, show the SAN the leaf carries, and
%% connect to the string IP with the https match_fun.
test_data_case(Dir) ->
    San = #'Extension'{extnID = ?'id-ce-subjectAltName',
                       extnValue = [{iPAddress, <<127, 0, 0, 1>>}],
                       critical = false},
    Conf = public_key:pkix_test_data(#{root => [{key, {rsa, 2048, 65537}}],
                                       intermediates => [],
                                       peer => [{key, {rsa, 2048, 65537}}, {extensions, [San]}]}),
    io:format("pkix_test_data keys: ~p~n", [proplists:get_keys(Conf)]),
    Cert = proplists:get_value(cert, Conf),
    Otp = public_key:pkix_decode_cert(Cert, otp),
    Exts = (Otp#'OTPCertificate'.tbsCertificate)#'OTPTBSCertificate'.extensions,
    Sans = [E#'Extension'.extnValue || E <- Exts, E#'Extension'.extnID =:= ?'id-ce-subjectAltName'],
    io:format("peer subjectAltName: ~p~n", [Sans]),
    CaCerts = proplists:get_value(cacerts, Conf),
    io:format("cacerts entries: ~b, distinct: ~b~n", [length(CaCerts), length(lists:usort(CaCerts))]),
    CaPem = filename:join(Dir, "test-data-ca.pem"),
    ok = file:write_file(CaPem, public_key:pem_encode([{'Certificate', C, not_encrypted} || C <- lists:usort(CaCerts)])),
    {ok, L} = ssl:listen(0, [{ip, {127, 0, 0, 1}}, {reuseaddr, true}, {active, false}, binary,
                             {cert, Cert}, {key, proplists:get_value(key, Conf)}]),
    {ok, {_, Port}} = ssl:sockname(L),
    spawn_link(fun() -> accept(L) end),
    Got = httpc:request(get, {"https://127.0.0.1:" ++ integer_to_list(Port) ++ "/", []},
                        [{ssl, opts(CaPem)}, {timeout, 5000}], [{body_format, binary}]),
    report("httpc GET against a pkix_test_data chain with an IP SAN", ok, Got, matches(ok, Got)).

report(Label, Want, Got, Ok) ->
    io:format("~s ~-52s want ~-12s got ~ts~n",
              [case Ok of true -> "ok  "; false -> "FAIL" end, Label, Want, oneline(Got)]),
    Ok.

matches(ok, {ok, {{_, Status, _}, _, _}}) -> Status =:= 200;
matches(ok, {ok, _}) -> true;
matches(unknown_ca, {error, {tls_alert, {unknown_ca, _}}}) -> true;
matches(unknown_ca, {error, {failed_connect, Reasons}}) ->
    lists:any(fun({inet, _, {tls_alert, {unknown_ca, _}}}) -> true; (_) -> false end, Reasons);
matches(econnrefused, {error, {failed_connect, Reasons}}) ->
    lists:any(fun({inet, _, econnrefused}) -> true; (_) -> false end, Reasons);
matches(hostname, {error, {tls_alert, {bad_certificate, Msg}}}) ->
    string:find(Msg, "hostname_check_failed") =/= nomatch;
matches(_, _) -> false.

oneline(T) ->
    re:replace(io_lib:format("~tp", [T]), "\\s+", " ", [global, unicode, {return, list}]).
