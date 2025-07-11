ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.3.3
ARG DISTRO=noble-20250404
ARG NODE_VERSION=16.20.2

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${DISTRO}"
ARG RUNNER_IMAGE="ubuntu:${DISTRO}"
ARG DEBIAN_FRONTEND=noninteractive

###
### First Stage - Fetch deps for building web assets
###
FROM ${BUILDER_IMAGE} as deps

ENV MIX_ENV=prod

RUN apt-get update && apt-get install -y git
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /build

COPY mix.* ./
RUN mix deps.get --only $MIX_ENV


###
### Second Stage - Build web assets
###
FROM node:${NODE_VERSION} as assets

RUN mkdir -p /priv/static

WORKDIR /build

COPY --from=deps /build/deps deps
COPY assets assets

WORKDIR /build/assets

# RUN npm install -g npm@10.2.4
RUN npm ci && npm cache clean --force && npm run deploy


###
### Third Stage - Building the Release
###
FROM ${BUILDER_IMAGE} as build

# install dependencies
RUN apt-get update -y && apt-get install -y build-essential git ca-certificates curl gnupg \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /build

ENV HEX_HTTP_TIMEOUT=20

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod
ENV SECRET_KEY_BASE=nokey

COPY mix.lock ./

RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/

COPY mix.exs .
RUN mix deps.get --only $MIX_ENV

RUN mix deps.compile

COPY priv priv
COPY lib lib

# Bring all the needed JS and built node assets from previous step
COPY --from=assets /build/assets assets
COPY --from=assets /build/priv/static priv/static

# We need the git history for creating the project version in Mix
COPY .git .git

RUN mix compile
RUN mix assets.deploy
RUN mix sentry.package_source_code

COPY config/runtime.exs config/

COPY rel rel

RUN mix release


###
### Last Stage - Setup the Runtime Environment
###

FROM ${RUNNER_IMAGE} AS app

RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses6 locales bash openssl curl python3 python3-pip jq xdelta3 zip unzip wget \
    && wget https://github.com/fwup-home/fwup/releases/download/v1.13.0/fwup_1.13.0_amd64.deb \
    && dpkg -i fwup_1.13.0_amd64.deb && rm fwup_1.13.0_amd64.deb \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app

COPY --from=build /build/_build/prod/rel/nerves_hub ./

ENV HOME=/app
ENV MIX_ENV=prod
ENV SECRET_KEY_BASE=nokey
ENV PORT=4000

ENTRYPOINT ["bin/nerves_hub"]
CMD ["start"]
