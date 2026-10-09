%% Tooling only: compiled into an ignored run directory, never the application.
-module(coverage_ffi).
-behaviour(eunit_listener).
-export([boot/0, start/1, init/1, handle_begin/3, handle_end/3,
        handle_cancel/3, terminate/2]).

boot() ->
    Directory = os:getenv("KNARR_COVERAGE_DIR"),
    {ok, Input} = file:read_file(filename:join(Directory, "inventory.json")),
    Entries = json:decode(Input),
    {ok, _} = cover:start(),
    ok = cover:local_only(),
    lists:foreach(fun(#{<<"module">> := Name, <<"beam">> := Beam}) ->
        Module = binary_to_atom(Name, utf8),
        {ok, Module} = cover:compile_beam(binary_to_list(Beam))
    end, Entries),
    Existing = case os:getenv("EUNIT") of
        false -> [];
        Text ->
            {ok, Tokens, _} = erl_scan:string(Text),
            {ok, Term} = erl_parse:parse_term(Tokens ++ [{dot, erl_anno:new(1)}]),
            case is_list(Term) of true -> Term; false -> [Term] end
    end,
    Options = Existing ++ [{report, {?MODULE, []}}],
    true = os:putenv("EUNIT", lists:flatten(io_lib:format("~p", [Options]))),
    ok.

start(Options) -> eunit_listener:start(?MODULE, Options).
init(_Options) -> ok.
handle_begin(_Kind, _Data, State) -> State.
handle_end(_Kind, _Data, State) -> State.
handle_cancel(_Kind, _Data, State) -> State.

terminate({ok, _Summary}, _State) ->
    Directory = os:getenv("KNARR_COVERAGE_DIR"),
    {ok, Input} = file:read_file(filename:join(Directory, "inventory.json")),
    Entries = json:decode(Input),
    Data = maps:from_list(lists:map(fun(#{<<"module">> := Name}) ->
        Module = binary_to_existing_atom(Name, utf8),
        {ok, Rows} = cover:analyse(Module, coverage, line),
        {Name, [[Line, Covered] || {{_, Line}, {Covered, _}} <- Rows]}
    end, Entries)),
    Temporary = filename:join(Directory, "raw.json.tmp"),
    ok = file:write_file(Temporary, json:encode(Data)),
    ok = file:rename(Temporary, filename:join(Directory, "raw.json"));
terminate(_Reason, _State) -> ok.
