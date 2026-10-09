-module(runtime_test_ffi).
-export([recover/1, occupied_port/1]).

recover({runtime, Root, State}) ->
  unlink(Root),
  try
    {ok, _} = application:ensure_all_started(inets),
    Port = atomics:get(State, 2),
    loopback_listener(Port),
    {200, <<"ok\n">>} = get(Port, "/healthz"),
    {200, <<"ok\n">>} = get(Port, "/readyz"),
    {200, Before} = get(Port, "/metrics"),
    true = binary:match(Before, <<"knarr_startups_total 1\n">>) =/= nomatch,
    [{_, Child, supervisor, _}] = supervisor:which_children(Root),
    Monitor = monitor(process, Child),
    exit(Child, kill),
    receive {'DOWN', Monitor, process, Child, killed} -> ok after 2000 -> error(no_crash) end,
    await(fun() ->
      [{_, NewChild, supervisor, _}] = supervisor:which_children(Root),
      true = is_pid(NewChild) andalso NewChild =/= Child,
      NewPort = atomics:get(State, 2),
      loopback_listener(NewPort),
      {200, <<"ok\n">>} = get(NewPort, "/healthz"),
      {200, <<"ok\n">>} = get(NewPort, "/readyz"),
      {200, After} = get(NewPort, "/metrics"),
      true = binary:match(After, <<"knarr_startups_total 1\n">>) =/= nomatch,
      true = binary:match(After, <<"erlang_vm_">>) =/= nomatch,
      true
    end, 100)
  after
    gen_server:stop(Root, shutdown, 5000)
  end.

loopback_listener(Port) ->
  true = Port > 0,
  [{127,0,0,1}] = [Address || Socket <- erlang:ports(),
    {ok, {Address, SocketPort}} <- [try inet:sockname(Socket) catch _:_ -> error end], SocketPort =:= Port].

get(Port, Path) ->
  Url = "http://127.0.0.1:" ++ integer_to_list(Port) ++ Path,
  {ok, {{_, Code, _}, _, Body}} = httpc:request(get, {Url, []}, [{timeout, 1000}], [{body_format, binary}]),
  {Code, Body}.

await(_Check, 0) -> error(recovery_timeout);
await(Check, Attempts) ->
  try Check() catch _:_ -> timer:sleep(20), await(Check, Attempts - 1) end.

occupied_port(Start) ->
  Previous = process_flag(trap_exit, true),
  {ok, Socket} = gen_tcp:listen(0, [{ip, {127,0,0,1}}]),
  {ok, {_, Port}} = inet:sockname(Socket),
  try
    case Start(Port) of
      {error, _} -> true;
      {ok, {started, Pid, _}} -> unlink(Pid), gen_server:stop(Pid), false
    end
  after
    gen_tcp:close(Socket),
    receive {'EXIT', _, _} -> ok after 100 -> ok end,
    process_flag(trap_exit, Previous)
  end.
