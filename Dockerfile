ARG ELIXIR_VERSION=1.15.7
ARG OTP_VERSION=26.1.2
ARG DISTRO=jammy-20231004

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${DISTRO}"
ARG RUNNER_IMAGE="ubuntu:${DISTRO}"
ARG DEBIAN_FRONTEND=noninteractive

###
### Fist Stage - Building the Release
###
FROM ${BUILDER_IMAGE} as build

# install dependencies
RUN apt-get update -y && apt-get install -y build-essential git ca-certificates curl gnupg \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && apt-get update -y && apt-get install -y nodejs && npm install -g npm

WORKDIR /build

ENV HEX_HTTP_TIMEOUT=20

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod
ENV SECRET_KEY_BASE=nokey

COPY bin/* bin/
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
COPY assets assets

WORKDIR /build/assets

RUN npm ci && npm cache clean --force && npm run deploy

WORKDIR /build

RUN mix compile
RUN mix phx.digest
RUN mix sentry.package_source_code

COPY config/runtime.exs config/

COPY rel rel

RUN mix release


###
### Second Stage - Setup the Runtime Environment
###

FROM ${RUNNER_IMAGE} AS app

RUN apt-get update -y \
  && apt-get install -y libstdc++6 openssl libncurses5 locales bash openssl curl python3 python3-pip jq xdelta3 zip unzip wget \
  && wget https://github.com/fwup-home/fwup/releases/download/v1.10.1/fwup_1.10.1_amd64.deb \
  && dpkg -i fwup_1.10.1_amd64.deb && rm fwup_1.10.1_amd64.deb \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app

COPY --from=build --chown=nobody:nobody /build/_build/prod/rel/nerves_hub ./

ENV HOME=/app
ENV MIX_ENV=prod
ENV SECRET_KEY_BASE=nokey
ENV PORT=4000

ENTRYPOINT ["bin/nerves_hub"]
CMD ["start"]
