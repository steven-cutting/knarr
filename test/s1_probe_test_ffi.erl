-module(s1_probe_test_ffi).
-export([children/1, await_new_child/2, stop_probe/1, stop_root/1, write_file/2, delete_file/1]).

%% The pids of a supervisor's children, in child id order.
children(Supervisor) ->
  [Pid || {_, Pid, _, _} <- lists:reverse(supervisor:which_children(Supervisor)), is_pid(Pid)].

await_new_child(Supervisor, Previous) -> await_new_child(Supervisor, Previous, 100).

await_new_child(_Supervisor, _Previous, 0) -> error(no_restart);
await_new_child(Supervisor, Previous, Attempts) ->
  case children(Supervisor) of
    [Pid] when Pid =/= Previous -> Pid;
    _ -> timer:sleep(20), await_new_child(Supervisor, Previous, Attempts - 1)
  end.

%% A bare actor is stopped the way its supervisor would stop it: an exit
%% signal, which it does not trap. A supervisor takes gen_server:stop.
stop_probe(Pid) ->
  unlink(Pid),
  exit(Pid, shutdown),
  nil.

stop_root(Pid) ->
  unlink(Pid),
  gen_server:stop(Pid, shutdown, 5000),
  nil.

%% Test fixtures under build/. The directory is created on the way.
write_file(Path, Content) ->
  ok = filelib:ensure_dir(Path),
  ok = file:write_file(Path, Content),
  nil.

delete_file(Path) ->
  ok = filelib:ensure_dir(Path),
  case file:delete(Path) of
    ok -> nil;
    {error, enoent} -> nil
  end.
