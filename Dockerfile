ARG ELIXIR_VERSION=1.13.2
ARG ERLANG_VERSION=23.0.4
ARG ALPINE_VERSION=3.13.1
ARG NODE_VERSION=16.18.1

# Fetch deps for building web assets
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-alpine-${ALPINE_VERSION} as deps
RUN apk --no-cache add git
RUN mix local.hex --force && mix local.rebar --force
ADD . /build
WORKDIR /build
RUN mix deps.clean --all && mix deps.get

# Build web assets
FROM node:${NODE_VERSION} as assets
RUN mkdir -p /priv/static
WORKDIR /build
COPY assets assets
COPY --from=deps /build/deps deps
RUN cd assets \
  && npm install \
  && npm run deploy

# Elixir build container
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-alpine-${ALPINE_VERSION} as builder

ENV MIX_ENV=prod

RUN apk --no-cache add build-base git curl sudo
RUN mix local.hex --force && mix local.rebar --force
RUN mkdir /build
ADD . /build
WORKDIR /build
COPY --from=deps /build/deps deps
COPY --from=assets /build/priv/static priv/static

RUN mix do phx.digest, release nerves_hub_www --overwrite

# Release Container
FROM nerveshub/runtime:alpine-${ALPINE_VERSION} as release
RUN apk add -X https://dl-cdn.alpinelinux.org/alpine/v3.15/main -u alpine-keys

RUN apk add 'fwup~=1.9' \
  --repository http://dl-cdn.alpinelinux.org/alpine/edge/community/ \
  --no-cache

RUN apk --no-cache add xdelta3 zip unzip

EXPOSE 80
EXPOSE 443

ENV LOCAL_IPV4=127.0.0.1
ENV URL_SCHEME=https \
  URL_PORT=443

COPY --from=builder /build/_build/$MIX_ENV/rel/nerves_hub_www/ ./
COPY --from=builder /build/rel/scripts/docker-entrypoint.sh .
COPY --from=builder /build/rel/scripts/ecs-cluster.sh .

RUN ["chmod", "+x", "/app/docker-entrypoint.sh"]
RUN ["chmod", "+x", "/app/ecs-cluster.sh"]

ENTRYPOINT ["/app/docker-entrypoint.sh"]

CMD ["/app/ecs-cluster.sh"]
