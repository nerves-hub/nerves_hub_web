ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29.1.2
# The builder pins a snapshot because hexpm publishes one tag per snapshot. The
# runner follows Ubuntu's release tag, so each build starts from the newest
# snapshot and nobody has to remember to bump it. Keep both on the same release:
# the release ships an ERTS linked against that release's glibc and OpenSSL.
ARG DISTRO=resolute-20261024.1
ARG NODE_VERSION=24.13.1
# Firmware that requires a newer fwup than this one is rejected on upload, so
# keep this at or above the fwup that Nerves systems build with.
ARG FWUP_VERSION=1.17.1
# fwup links libarchive statically and reads customer uploads with it, and no
# image scanner can see a version inside that binary. fwup 1.17.1 pins 3.8.9,
# which later security releases fix, so override it until fwup catches up.
ARG LIBARCHIVE_VERSION=3.8.11
ARG LIBARCHIVE_SHA256=900fe9fc7237c2b04f090f3c3648de8fe597525771f5035016537ce2d667d12b

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${DISTRO}"
ARG RUNNER_IMAGE="ubuntu:resolute"
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
RUN npm ci && npm cache clean --force


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

ARG FWUP_VERSION
ARG LIBARCHIVE_VERSION
ARG LIBARCHIVE_SHA256

# The version is in the clone itself, so a cached clone from before the tag
# can't be reused.
RUN git clone --depth 1 --branch v${FWUP_VERSION} https://github.com/fwup-home/fwup /tmp/fwup

WORKDIR /tmp/fwup

RUN sed -i "s/^LIBARCHIVE_VERSION=.*/LIBARCHIVE_VERSION=${LIBARCHIVE_VERSION}/" scripts/third_party_versions.sh && \
    sed -i "s/^.*libarchive-.*$/${LIBARCHIVE_SHA256}  libarchive-${LIBARCHIVE_VERSION}.tar.gz/" scripts/third_party.sha256 && \
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
    apt-get install -y git autoconf cmake make gcc-14 g++-14 && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 14 --slave /usr/bin/g++ g++ /usr/bin/g++-14

# The version is part of the clone, so bumping it changes this layer. A clone
# in a layer of its own is cached by its command alone and goes stale, and the
# checkout after it then cannot find a newer tag.
RUN git clone --depth 1 --branch 5.4.0 https://github.com/jemalloc/jemalloc /tmp/jemalloc

WORKDIR /tmp/jemalloc

RUN autoconf && \
    ./configure && \
    make && \
    make install


###
### detools, which builds the deltas for ESP-IDF firmware
###

FROM ${RUNNER_IMAGE} AS detools

ARG DEBIAN_FRONTEND

# detools carries a C extension and publishes no wheel for the Python this
# image ships, so pip builds it from source. That needs a compiler, which is
# why this is a stage of its own: only the finished virtualenv is copied into
# the runtime image, and the toolchain stays here.
RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y python3 python3-venv python3-dev build-essential

# Pinned, because the patch format is a contract with devices in the field. A
# later release changing a default would change what a patch is, and a device
# would find out by failing to apply one. The flags are pinned to match in
# NervesHub.Firmwares.UpdateTool.EspIdf.
RUN python3 -m venv /opt/detools && \
    /opt/detools/bin/pip install --no-cache-dir detools==0.53.0 && \
    rm -rf /opt/detools/lib/python*/site-packages/pip \
           /opt/detools/lib/python*/site-packages/pip-* \
           /opt/detools/bin/pip*


###
### Last Stage - Setup the Runtime Environment
###

FROM ${RUNNER_IMAGE} AS app

RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends openssl ca-certificates locales bash xdelta3 zip libsctp1 python3 && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Pebble is the service manager Ubuntu's image is built with. Nothing here runs
# it, and no package owns it, so apt can never patch it. Setuid binaries are only
# useful for changing user, which a container has no reason to do. The user has a
# fixed numeric id so that Kubernetes' runAsNonRoot can check it.
RUN rm -f /usr/bin/pebble && \
    find / -xdev -type f -perm /6000 -exec chmod a-s {} + && \
    groupadd --gid 65532 nerveshub && \
    useradd --uid 65532 --gid 65532 --home-dir /app --no-create-home --shell /usr/sbin/nologin nerveshub

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

# The virtualenv references the system python3 by absolute path, so it has to
# land where it was built and the runtime has to have that interpreter.
COPY --from=detools /opt/detools /opt/detools
RUN ln -s /opt/detools/bin/detools /usr/local/bin/detools

# Copy over NervesHub
WORKDIR /app

# Root keeps ownership so that the app can read its own code but not rewrite it.
# The app writes TLS files and crash dumps to /app/tmp, the only place under /app
# it can write.
COPY --from=build /build/_build/prod/rel/nerves_hub ./
RUN mkdir tmp && \
    chown 65532:65532 tmp

ENV HOME=/app
ENV MIX_ENV=prod
ENV PORT=4000
ENV ERL_CRASH_DUMP=/app/tmp/erl_crash.dump

USER 65532:65532

ENTRYPOINT ["bin/nerves_hub"]

CMD ["start"]
