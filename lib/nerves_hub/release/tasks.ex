defmodule NervesHub.Release.Tasks do
  alias Ecto.Migrator

  @app :nerves_hub
  @migrate_opts [
    pool_size: 10,
    start_apps_before_migration: [:logger, :ssl, :postgrex, :ecto_sql]
  ]

  @doc """
  Run the Ecto.Migrator for each defined repo

  You can optionally pass options supported Ecto.Migrator.run/3 for each
  repo in order to control the migration a bit more, like for specifying
  a migration to stop at:

    migrate([{NervesHub.Repo, [to: 20240806112233]}])
  """
  @spec migrate([{Ecto.Repo.t(), keyword()}]) :: [{:ok, [integer()], [atom()]} | {:error, term()}]
  def migrate(opts \\ []) do
    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      run_opts = opts[repo] || [all: true]
      {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :up, run_opts), @migrate_opts)
    end
  end

  def migrate_and_seed(opts \\ []) do
    _ = migrate(opts)
    seed()
  end

  def rollback(repo \\ NervesHub.Repo, version) do
    {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :down, to: version), @migrate_opts)
  end

  def seed() do
    with priv_path when is_list(priv_path) or is_binary(priv_path) <- :code.priv_dir(@app),
         seed_script = Path.join(priv_path, "repo/seeds.exs"),
         true <- File.exists?(seed_script),
         {:ok, _, _} <-
           Migrator.with_repo(
             NervesHub.Repo,
             fn _ -> Code.eval_file(seed_script) end,
             @migrate_opts
           ) do
      :ok
    else
      err ->
        raise "Failed to run seed script: #{inspect(err)}"
    end
  end
end
