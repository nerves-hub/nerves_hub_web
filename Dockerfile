ARG ELIXIR_VERSION=1.15.4
ARG ERLANG_VERSION=26.0.2
ARG ALPINE_VERSION=3.18.2
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

RUN mix do phx.digest, release nerves_hub --overwrite

# Release Container
FROM alpine:${ALPINE_VERSION} as release

ENV MIX_ENV=prod
ENV REPLACE_OS_VARS true
ENV LC_ALL=en_US.UTF-8
ENV AWS_ENV_SHA=1393537837dc67d237a9a31c8b4d3dd994022d65e99c1c1e1968edc347aae63f

ARG AWS_CLI_VERSION=1.22.81
RUN apk --no-cache add \
  bash \
  libcrypto1.1 \
  openssl \
  curl \
  python3 \
  py-pip \
  jq \
  && pip install --no-cache-dir awscli==$AWS_CLI_VERSION

# Add SSM Parameter Store helper, which is used in the entrypoint script to set secrets
RUN wget https://raw.githubusercontent.com/nerves-hub/aws-env/master/bin/aws-env-linux-amd64 && \
    echo "$AWS_ENV_SHA  aws-env-linux-amd64" | sha256sum -c - && \
    mv aws-env-linux-amd64 /bin/aws-env && \
    chmod +x /bin/aws-env

WORKDIR /app

RUN apk add --no-cache fwup xdelta3 zip unzip

EXPOSE 80
EXPOSE 443

ENV LOCAL_IPV4=127.0.0.1
ENV URL_SCHEME=https \
  URL_PORT=443

COPY --from=builder /build/_build/$MIX_ENV/rel/nerves_hub/ ./
COPY --from=builder /build/rel/scripts/docker-entrypoint.sh .
COPY --from=builder /build/rel/scripts/s3-sync.sh .
COPY --from=builder /build/rel/scripts/ecs-cluster.sh .

RUN ["chmod", "+x", "/app/docker-entrypoint.sh"]
RUN ["chmod", "+x", "/app/s3-sync.sh"]
RUN ["chmod", "+x", "/app/ecs-cluster.sh"]

ENTRYPOINT ["/app/docker-entrypoint.sh"]

CMD ["/app/ecs-cluster.sh"]
