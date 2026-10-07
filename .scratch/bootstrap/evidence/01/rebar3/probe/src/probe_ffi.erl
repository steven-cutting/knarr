-module(probe_ffi).
-export([count_twice/0]).

%% Starts the prometheus application rebar3 compiled and uses one counter.
count_twice() ->
    {ok, _} = application:ensure_all_started(prometheus),
    prometheus_counter:declare([{name, knarr_probe_total}, {help, "ticket 01 probe"}]),
    prometheus_counter:inc(knarr_probe_total),
    prometheus_counter:inc(knarr_probe_total),
    prometheus_counter:value(knarr_probe_total).
