help:
	@echo "Make targets:"
	@echo
	@echo "server - start the server"
	@echo "iex-server - start the server with the interactive shell"
	@echo "reset-db - reinitialize the database"
	@echo "test - run the unit tests"

.env:
	@echo "Please create a '.env' file first. Copy 'dev.env' to '.env' for a start."
	@exit 1

server: .env
	. ./.env && \
	mix phx.server

iex:
	make iex-server

iex-server: .env
	. ./.env && \
	iex -S mix phx.server

mix:
	iex -S mix

format:
	mix cmd mix format

check-format:
	mix cmd mix format --check-formatted

reset-db: .env
	. ./.env && \
	make rebuild-db

rebuild-db:
	mix ecto.drop && \
	mix ecto.create && \
	mix ecto.migrate && \
	mix run apps/nerves_hub_web_core/priv/repo/seeds.exs

test: .env
	MIX_ENV=test \
	. ./.env && \
	mix test

test-watch: .env
	MIX_ENV=test \
	. ./.env && \
	mix test.watch

.PHONY: test rebuild-db reset-db mix iex-server server help
