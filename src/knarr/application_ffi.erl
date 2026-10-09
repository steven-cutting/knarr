-module(application_ffi).
-behaviour(application).
-export([start/2, stop/1, await_shutdown/0]).

start(_Type, _Args) ->
  metrics_ffi:startup(),
  Port = application:get_env(knarr, port, 8080),
  Bind = unicode:characters_to_binary(application:get_env(knarr, bind, "0.0.0.0")),
  case 'knarr@runtime':start(Port, Bind) of
    {ok, {started, Pid, _Runtime}} -> {ok, Pid};
    {error, Reason} -> {error, Reason}
  end.

stop(_State) -> ok.

await_shutdown() ->
  {ok, Root} = application:get_supervisor(knarr),
  Monitor = monitor(process, Root),
  receive
    {'DOWN', Monitor, process, Root, Reason} ->
      case init:get_status() of
        {stopping, _} -> receive after infinity -> ok end;
        _ -> exit({knarr_stopped, Reason})
      end
  end.
