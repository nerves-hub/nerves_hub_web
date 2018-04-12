server: .env
	source .env && \
	mix phx.server

.env:
	@echo "Please create a '.env' file first. Copy 'dev.env' to '.env' for a start."
	@exit 1

iex:
	make iex-server

iex-server: .env
	source .env && \
	iex -S mix phx.server

mix:
	iex -S mix

reset-db: .env
	source .env && \
	make rebuild-db

rebuild-db:
	mix ecto.drop && \
	mix ecto.create && \
	mix ecto.migrate && \
	mix run priv/repo/seeds.exs

test: .env
	source .env && \
	    MIX_ENV=test mix test

.PHONY: test rebuild-db reset-db mix iex-server server
