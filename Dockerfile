ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.3.1
ARG DISTRO=noble-20260210.1
ARG NODE_VERSION=16.20.2

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${DISTRO}"
ARG RUNNER_IMAGE="ubuntu:${DISTRO}"
ARG DEBIAN_FRONTEND=noninteractive

###
### Fetch deps for building web assets
###
FROM ${BUILDER_IMAGE} AS deps

ENV MIX_ENV=prod

RUN apt-get update && apt-get install -y git
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /build

COPY mix.* ./
RUN mix deps.get --only $MIX_ENV


###
### Build web assets
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
### Build the NervesHub release
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
### Build a static FWUP
###

FROM ${RUNNER_IMAGE} AS fwup

RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y git curl build-essential autoconf pkg-config libtool mtools unzip zip help2man libconfuse-dev libarchive-dev xdelta3 dosfstools

RUN git clone https://github.com/fwup-home/fwup /tmp/fwup

WORKDIR /tmp/fwup

# pinning to 428350a as it fixes dependency download URL issues
RUN git checkout 428350a && \
    ./scripts/download_deps.sh && \
    ./scripts/build_deps.sh && \
    ./autogen.sh && \
    PKG_CONFIG_PATH=$PWD/build/host/deps/usr/lib/pkgconfig ./configure --enable-shared=no && \
    make && \
    make check && \
    make install


###
### Build jemalloc - GCC 14
###

FROM ${RUNNER_IMAGE} AS jemalloc

RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y git autoconf cmake make software-properties-common && \
    add-apt-repository ppa:ubuntu-toolchain-r/ppa -y && \
    apt-get update -y && \
    apt-get install -y gcc-14 g++-14 && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 14 --slave /usr/bin/g++ g++ /usr/bin/g++-14

# Build the latest jemalloc

RUN git clone https://github.com/facebook/jemalloc /tmp/jemalloc

WORKDIR /tmp/jemalloc

RUN autoconf && \
    ./configure && \
    make && \
    make install


###
### Last Stage - Setup the Runtime Environment
###

FROM ${RUNNER_IMAGE} AS app

RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y openssl ca-certificates locales bash xdelta3 zip unzip && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Use jemalloc for memory allocation
COPY --from=jemalloc /usr/local/lib/libjemalloc.so.2 /usr/local/lib/libjemalloc.so.2
ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so.2

# Copy over the statically built fwup
COPY --from=fwup /usr/local/bin/fwup /usr/local/bin/fwup

# Copy over NervesHub
WORKDIR /app

COPY --from=build /build/_build/prod/rel/nerves_hub ./

ENV HOME=/app
ENV MIX_ENV=prod
ENV SECRET_KEY_BASE=nokey
ENV PORT=4000

ENTRYPOINT ["bin/nerves_hub"]

CMD ["start"]
