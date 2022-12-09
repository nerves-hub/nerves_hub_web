defmodule NervesHubWebCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :nerves_hub_web_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      compilers: Mix.compilers(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.post": :test,
        docs: :docs
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in [:dev, :test],
    do: ["lib", "test/support", Path.expand("../../test/support")]

  defp elixirc_paths(_),
    do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {NervesHubWebCore.Application, []},
      extra_applications: [:logger, :jason, :inets, :base62],
      start_phases: [{:start_workers, []}]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.6"},
      {:phoenix_html, "~> 3.1"},
      {:phoenix_live_view, "~> 0.16"},
      {:plug, "~> 1.7"},
      {:plug_cowboy, "~> 2.1"},
      {:ecto_sql, "~> 3.0"},
      {:ecto_enum, github: "gjaldon/ecto_enum"},
      {:postgrex, "~> 0.14"},
      {:bcrypt_elixir, "~> 3.0"},
      {:comeonin, "~> 5.3"},
      {:oban, "~> 2.8"},
      {:crontab, "~> 1.1"},
      {:timex, "~> 3.1"},
      {:sweet_xml, "~> 0.6"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:x509, "~> 0.5.1 or ~> 0.6"},
      {:bamboo, "~> 2.0"},
      {:bamboo_phoenix, "~> 1.0"},
      {:bamboo_smtp, "~> 4.1"},
      {:jason, "~> 1.2", override: true},
      {:ecto, "~> 3.4", override: true},
      {:mox, "~> 1.0", only: [:test, :dev]},
      {:nimble_csv, "~> 1.1"},
      {:base62, "~> 1.2"},
      {:scrivener_ecto, "~> 2.7"}
    ]
  end
end
