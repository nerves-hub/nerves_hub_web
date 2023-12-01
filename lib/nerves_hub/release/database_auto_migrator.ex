defmodule NervesHub.Release.DatabaseAutoMigrator do
  @moduledoc """
  Run migrations during App startup

  A useful addition for deploying to cloud environments
  https://elixirforum.com/t/running-migrations-on-google-cloud-run/38773
  """

  alias Ecto.Migrator

  require Logger

  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], [])
  end

  def init(_) do
    migrate!()
    {:ok, nil}
  end

  def migrate! do
    if Application.get_env(:nerves_hub, :database_auto_migrator) do
      Logger.info("Database auto migrator enabled and preparing to run migrations")

      path = Application.app_dir(:nerves_hub, "priv/repo/migrations")

      Migrator.run(NervesHub.Repo, path, :up, all: true)
    else
      Logger.info("Database auto migrator not enabled")
    end
  end
end
