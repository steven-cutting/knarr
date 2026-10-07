#!/usr/bin/env escript
%% Ticket 01 evidence, Verify 1: the OTP from the pixi environment completes a
%% verify_peer handshake against an explicit cacertfile with an https hostname
%% check, by DNS name and by IP SAN, and refuses a wrong CA, a wrong name and a
%% missing IP SAN with the expected alert. Server and client are both this OTP.
%% Usage: escript tls_check.escript <cert-dir>   (exit 0 only if every case matches)
-mode(compile).

main([Dir]) ->
    %% The alerts are the expected outcome of four cases; keep their NOTICE
    %% reports out of the transcript, which prints each result itself.
    ok = logger:set_primary_config(level, warning),
    {ok, _} = application:ensure_all_started(ssl),
    io:format("otp_release ~s, erts ~s~n",
              [erlang:system_info(otp_release), erlang:system_info(version)]),
    io:format("crypto:info_lib() ~p~n", [crypto:info_lib()]),
    io:format("ssl:versions() ~p~n", [proplists:get_value(supported, ssl:versions())]),
    F = fun(Name) -> filename:join(Dir, Name) end,
    Full = listen(F("server.pem"), F("server.key")),
    DnsOnly = listen(F("server-dns.pem"), F("server-dns.key")),
    CaA = F("ca-a.pem"),
    CaB = F("ca-b.pem"),
    Cases =
        [{"right CA, by name localhost", "localhost", Full, CaA, [], ok},
         {"right CA, by IP tuple (IP SAN)", {127, 0, 0, 1}, Full, CaA, [], ok},
         {"wrong CA (ca-b), by name", "localhost", Full, CaB, [], unknown_ca},
         {"wrong CA (ca-b), by IP tuple", {127, 0, 0, 1}, Full, CaB, [], unknown_ca},
         {"right CA, wrong name (SNI wrong.example)", "localhost", Full, CaA,
          [{server_name_indication, "wrong.example"}], hostname},
         {"right CA, IP tuple, cert has no IP SAN", {127, 0, 0, 1}, DnsOnly, CaA, [], hostname}],
    Results = [run(C) || C <- Cases],
    case lists:all(fun(R) -> R end, Results) of
        true -> io:format("tls_check: all ~b cases matched~n", [length(Results)]), halt(0);
        false -> io:format("tls_check: MISMATCH~n"), halt(1)
    end;
main(_) ->
    io:format("usage: tls_check.escript <cert-dir>~n"),
    halt(2).

listen(Cert, Key) ->
    {ok, L} = ssl:listen(0, [{ip, {127, 0, 0, 1}}, {certfile, Cert}, {keyfile, Key},
                             {reuseaddr, true}, {active, false}]),
    {ok, {_, Port}} = ssl:sockname(L),
    spawn_link(fun() -> accept(L) end),
    Port.

accept(L) ->
    {ok, T} = ssl:transport_accept(L),
    spawn(fun() -> _ = ssl:handshake(T, 5000), timer:sleep(500), ssl:close(T) end),
    accept(L).

run({Label, Host, Port, Ca, Extra, Want}) ->
    Opts = [{verify, verify_peer}, {cacertfile, Ca},
            {customize_hostname_check,
             [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]},
            {active, false} | Extra],
    Got = case ssl:connect(Host, Port, Opts, 5000) of
              {ok, S} ->
                  {ok, Info} = ssl:connection_information(S, [protocol, selected_cipher_suite]),
                  ssl:close(S),
                  {ok, Info};
              {error, E} -> {error, E}
          end,
    Ok = matches(Want, Got),
    io:format("~s ~-44s want ~-10s got ~ts~n",
              [case Ok of true -> "ok  "; false -> "FAIL" end, Label, Want, oneline(Got)]),
    Ok.

matches(ok, {ok, _}) -> true;
matches(unknown_ca, {error, {tls_alert, {unknown_ca, _}}}) -> true;
%% OTP 29 reports a failed hostname check as a bad_certificate alert whose
%% text carries {bad_cert, {hostname_check_failed, ...}}.
matches(hostname, {error, {tls_alert, {bad_certificate, Msg}}}) ->
    string:find(Msg, "hostname_check_failed") =/= nomatch;
matches(_, _) -> false.

oneline(T) ->
    re:replace(io_lib:format("~tp", [T]), "\\s+", " ", [global, unicode, {return, list}]).
