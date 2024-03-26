defmodule NervesHub.Release.Tasks do
  alias Ecto.Migrator

  @app :nerves_hub
  @migrate_opts [
    pool_size: 10,
    start_apps_before_migration: [:logger, :ssl, :postgrex, :ecto_sql]
  ]

  def migrate() do
    :ok = Application.ensure_started(:tls_certificate_check)

    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :up, all: true), @migrate_opts)
    end
  end

  def migrate_and_seed() do
    _ = migrate()
    seed()
  end

  def rollback(repo \\ NervesHub.Repo, version) do
    Application.load(@app)
    {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :down, to: version), @migrate_opts)
  end

  def seed() do
    Application.load(@app)

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
