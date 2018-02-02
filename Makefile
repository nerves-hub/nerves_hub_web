server:
	source .env && \
	mix phx.server

iex:
	make iex-server

iex-server:
	source .env && \
	iex -S mix phx.server

mix:
	iex -S mix

reset-db:
	source .env && \
	make rebuild-db

rebuild-db:
	mix ecto.drop && \
	mix ecto.create && \
	mix ecto.migrate && \
	mix run priv/repo/seeds.exs