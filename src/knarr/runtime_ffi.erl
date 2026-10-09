-module(runtime_ffi).
-export([new_state/0, ready/1, mark_ready/1, set_port/2]).

new_state() -> atomics:new(2, []).
ready(State) -> atomics:get(State, 1) =:= 1.
mark_ready(State) -> atomics:put(State, 1, 1), nil.
set_port(State, Port) -> atomics:put(State, 2, Port), nil.
