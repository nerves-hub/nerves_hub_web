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
FROM ${BUILDER_IMAGE} AS deps

ENV MIX_ENV=prod

RUN apt-get update && apt-get install -y git
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /build

COPY mix.* ./
RUN mix deps.get --only $MIX_ENV


###
### Second Stage - Build web assets
###
FROM node:${NODE_VERSION} AS assets

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
FROM ${BUILDER_IMAGE} AS build

# install dependencies
RUN apt-get update -y && apt-get install -y build-essential git ca-certificates curl gnupg && \
    apt-get clean && \
    rm -f /var/lib/apt/lists/*_*

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
    && apt-get install -y openssl locales bash jq xdelta3 libconfuse-dev zip unzip curl wget

COPY docker/ /tmp/install_scripts
RUN /tmp/install_scripts/fwup.sh && \
    /tmp/install_scripts/jemalloc.sh

# Clean up build dependencies and temporary files
RUN apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/install_scripts

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Use jemalloc for memory allocation
ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so

# Copy over NervesHub
WORKDIR /app

COPY --from=build /build/_build/prod/rel/nerves_hub ./

ENV HOME=/app
ENV MIX_ENV=prod
ENV SECRET_KEY_BASE=nokey
ENV PORT=4000

ENTRYPOINT ["bin/nerves_hub"]
CMD ["start"]
