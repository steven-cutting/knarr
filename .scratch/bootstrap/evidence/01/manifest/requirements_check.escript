#!/usr/bin/env escript
%% Ticket 01 evidence, Verify 5: a pre-check that never writes. gleam rewrites
%% manifest.toml whenever its [requirements] table disagrees with gleam.toml's
%% [dependencies] and [dev_dependencies], so compare those tables first.
%% Inputs are taplo's JSON for each table ("{}" for a missing one): the
%% manifest's [requirements] first, then every gleam.toml table that feeds it
%% ([dependencies], and [dev_dependencies] or [dev-dependencies]; gleam
%% accepts both spellings).
%% Usage: escript requirements_check.escript <manifest-requirements.json> <gleam-table.json>...
-mode(compile).

main([Reqs | Tables]) when Tables =/= [] ->
    Merged = lists:foldl(fun(T, Acc) -> maps:merge(Acc, read(T)) end, #{}, Tables),
    Want = maps:map(fun(_, V) -> normalise(V) end, Merged),
    Got = read(Reqs),
    case Want =:= Got of
        true ->
            io:format("manifest.toml [requirements] matches gleam.toml~n"),
            halt(0);
        false ->
            Keys = lists:usort(maps:keys(Want) ++ maps:keys(Got)),
            [io:format("  ~ts: gleam.toml ~ts, manifest.toml ~ts~n",
                       [K, show(maps:find(K, Want)), show(maps:find(K, Got))])
             || K <- Keys, maps:find(K, Want) =/= maps:find(K, Got)],
            io:format("manifest.toml disagrees with gleam.toml; run gleam deps download and commit it~n"),
            halt(1)
    end;
main(_) ->
    io:format("usage: requirements_check.escript <reqs.json> <gleam-table.json>...~n"),
    halt(2).

read(Path) ->
    {ok, Bin} = file:read_file(Path),
    json:decode(Bin).

%% gleam.toml allows a bare version string; the manifest always writes a table.
normalise(V) when is_binary(V) -> #{<<"version">> => V};
normalise(V) -> V.

show(error) -> "absent";
show({ok, V}) -> iolist_to_binary(json:encode(V)).
