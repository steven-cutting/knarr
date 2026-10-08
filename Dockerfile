FROM ghcr.io/prefix-dev/pixi:0.81.0 AS build
WORKDIR /opt/knarr
COPY pixi.toml pixi.lock ./
RUN pixi install --locked -e default -e runtime
ADD --checksum=sha256:708407032479514dd68b581a0b09a68b5a781fb6f53dcf4ad81ce4ef6b92940f https://github.com/erlang/rebar3/releases/download/3.27.1/rebar3 /opt/knarr/.tools/bin/rebar3
RUN chmod 0755 .tools/bin/rebar3
ENV PATH="/opt/knarr/.pixi/envs/default/bin:/opt/knarr/.tools/bin:${PATH}"
COPY gleam.toml manifest.toml ./
RUN gleam deps download
COPY src src
RUN gleam export erlang-shipment \
    && erl -noshell -eval 'io:put_chars(erlang:system_info(otp_release)), halt().' > /opt/build-otp

FROM ubuntu:24.04 AS runtime
WORKDIR /opt/knarr
COPY --from=build /opt/knarr/.pixi/envs/runtime /opt/knarr/.pixi/envs/runtime
COPY --from=build /opt/knarr/build/erlang-shipment /opt/knarr/shipment
COPY --from=build /opt/build-otp /opt/build-otp
ENV PATH="/opt/knarr/.pixi/envs/runtime/bin:${PATH}" \
    ERL_CRASH_DUMP=/tmp/erl_crash.dump
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/opt/knarr/shipment/entrypoint.sh"]
CMD ["run"]
