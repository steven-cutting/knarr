-module(metrics_ffi).
-export([startup/0, collect/0]).

startup() ->
  prometheus_counter:declare([{name, knarr_startups_total},
                            {help, "Application startups in this VM."}]),
  prometheus_counter:inc(knarr_startups_total),
  nil.

collect() -> prometheus_text_format:format().
