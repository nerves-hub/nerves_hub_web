ARG ELIXIR_VERSION=1.15.7
ARG ERLANG_VERSION=26.1.2
ARG NODE_VERSION=16.18.1

# Fetch deps for building web assets
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-debian-buster-20231009 as deps
RUN apt-get update && apt-get install -y git
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
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-debian-buster-20231009 as builder

ENV MIX_ENV=prod

RUN apt-get update && apt-get install -y build-essential git curl sudo
RUN mix local.hex --force && mix local.rebar --force
RUN mkdir /build
ADD . /build
WORKDIR /build
COPY --from=deps /build/deps deps
COPY --from=assets /build/priv/static priv/static

RUN mix do phx.digest, sentry.package_source_code, release nerves_hub --overwrite

# Release Container
FROM debian:buster-20231009 as release

ENV MIX_ENV=prod
ENV REPLACE_OS_VARS true
ENV LC_ALL=en_US.UTF-8
ENV AWS_ENV_SHA=1393537837dc67d237a9a31c8b4d3dd994022d65e99c1c1e1968edc347aae63f

RUN apt-get update && apt-get install -y bash openssl curl python3 python3-pip jq xdelta3 zip unzip wget && \
      wget https://github.com/fwup-home/fwup/releases/download/v1.10.1/fwup_1.10.1_amd64.deb && \
      dpkg -i fwup_1.10.1_amd64.deb && rm fwup_1.10.1_amd64.deb && \
      apt-get clean && rm -rf /var/lib/apt/lists/* && \
      pip3 install awscli==1.29.19 PyYAML==6.0.1

# Add SSM Parameter Store helper, which is used in the entrypoint script to set secrets
RUN wget https://raw.githubusercontent.com/nerves-hub/aws-env/master/bin/aws-env-linux-amd64 && \
    echo "$AWS_ENV_SHA  aws-env-linux-amd64" | sha256sum -c - && \
    mv aws-env-linux-amd64 /bin/aws-env && \
    chmod +x /bin/aws-env

WORKDIR /app

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
