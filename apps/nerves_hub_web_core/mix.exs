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
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      compilers: [:phoenix] ++ Mix.compilers(),
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
      {:bamboo_phoenix, "~> 1.0"},
      {:bamboo_smtp, "~> 4.0.0"},
      {:bamboo, "~> 2.0"},
      {:bark, github: "smartrent/bark", tag: "1.1.1"},
      {:base62, "~> 1.2"},
      {:bcrypt_elixir, "~> 3.0"},
      {:comeonin, "~> 5.3"},
      {:crontab, "~> 1.1"},
      {:decorator, "~> 1.2"},
      {:ecto_enum, github: "mobileoverlord/ecto_enum"},
      {:ecto_sql, "~> 3.0"},
      {:ecto, "~> 3.4", override: true},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws, "~> 2.0"},
      {:httpoison, "~> 1.4.0"},
      {:jason, "~> 1.2", override: true},
      {:mox, "~> 1.0", only: [:test, :dev]},
      {:nimble_csv, "~> 1.1"},
      {:oban, "~> 2.11"},
      {:phoenix_html, "~> 2.14"},
      {:phoenix, "~> 1.5"},
      {:plug_cowboy, "~> 2.1"},
      {:plug, "~> 1.7"},
      {:postgrex, "~> 0.14"},
      {:scrivener_ecto, "~> 2.7"},
      {:spandex_datadog, "~> 1.0.0"},
      {:spandex_ecto, "~> 0.6.2"},
      {:spandex_phoenix, "~> 1.0.0"},
      {:spandex, "~> 3.0.1"},
      {:statix, "~> 1.2"},
      {:sweet_xml, "~> 0.6"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_poller, "~> 0.4"},
      {:timex, "~> 3.1"},
      {:x509, "~> 0.5.1 or ~> 0.6"}
    ]
  end
end
