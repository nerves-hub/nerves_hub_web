FROM elixir:1.13

ENV \
  LANG=C.UTF-8 \
  LC_ALL=en_US.UTF-8 \
  PATH="/app:${PATH}" \
  FWUP_VERSION=1.9.0 \
  DATABASE_URL=postgres://db:db@localhost:5432/db \
  DATABASE_SSL="false" \
  SECRET_KEY_BASE=""

ADD . /app
WORKDIR /app

RUN apt-get update -y -qq \
  && apt-get -qq -y install \
    locales xdelta3 unzip zip \
  && export LANG=en_US.UTF-8 \
  && echo $LANG UTF-8 > /etc/locale.gen \
  && locale-gen \
  && update-locale LANG=$LANG
RUN wget https://github.com/fwup-home/fwup/releases/download/v${FWUP_VERSION}/fwup_${FWUP_VERSION}_amd64.deb \
  && dpkg -i ./fwup_${FWUP_VERSION}_amd64.deb \
  && rm -f fwup_${FWUP_VERSION}_amd64.deb
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get
RUN mix compile

EXPOSE 4000
EXPOSE 4001

CMD ["iex", "-S", "mix", "phx.server"]
