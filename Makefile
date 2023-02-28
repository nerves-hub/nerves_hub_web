help:
	@echo "Make targets:"
	@echo
	@echo "server - start the server"
	@echo "iex-server - start the server with the interactive shell"
	@echo "reset-db - reinitialize the database"
	@echo "reset-test-db - reinitialize the test database"
	@echo "test - run the unit tests"

server:
	mix phx.server

iex:
	iex -S mix

iex-server:
	iex -S mix phx.server

reset-db:
	mix exto.reset

reset-test-db:
	MIX_ENV=test \
	make reset-db

test:
	mix test

.PHONY: help server iex iex-server reset-db reset-test-db test
