defmodule NervesHubWWW.MixProject do
  use Mix.Project

  def project do
    [
      app: :nerves_hub_www,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      preferred_cli_env: [
        docs: :docs
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {NervesHubWWW.Application, []},
      extra_applications: [
        :logger,
        :runtime_tools,
        :timex,
        :jason,
        :inets,
        :base62
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in [:dev, :test],
    do: ["lib", "test/support", Path.expand("../../test/support")]

  defp elixirc_paths(_),
    do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ansi_to_html, git: "https://github.com/jjcarstens/ansi_to_html"},
      {:bamboo, "~> 2.0"},
      {:bamboo_phoenix, "~> 1.0"},
      {:bamboo_smtp, "~> 4.0.0"},
      {:bark, github: "smartrent/bark", tag: "1.1.1"},
      {:base62, "~> 1.2"},
      {:bcrypt_elixir, "~> 3.0"},
      {:comeonin, "~> 5.3"},
      {:cowboy, "~> 2.0", override: true},
      {:crontab, "~> 1.1"},
      {:decorator, "~> 1.2"},
      {:ecto, "~> 3.4", override: true},
      {:ecto_enum, github: "mobileoverlord/ecto_enum"},
      {:ecto_sql, "~> 3.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:floki, ">= 0.27.0", only: :test},
      {:gen_leader, github: "garret-smith/gen_leader_revival"},
      {:gettext, "~> 0.11"},
      {:gproc, "~> 0.9.0"},
      {:hackney, "~> 1.16"},
      {:httpoison, "~> 1.4.0"},
      {:jason, "~> 1.2", override: true},
      {:logfmt, "~> 3.3"},
      {:mox, "~> 1.0", only: [:test, :dev]},
      {:nimble_csv, "~> 1.1"},
      {:oban, "~> 2.11"},
      {:phoenix, "~> 1.5"},
      {:phoenix_active_link, "~> 0.3.1"},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_html, "~> 2.14"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.15"},
      {:phoenix_markdown, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:plug, "~> 1.7"},
      {:plug_cowboy, "~> 2.1"},
      {:postgrex, "~> 0.14"},
      {:scrivener_ecto, "~> 2.7"},
      {:scrivener_html, git: "https://github.com/nerves-hub/scrivener_html", branch: "phx-1.5"},
      {:slipstream, "~> 1.0", only: [:test, :dev]},
      {:spandex, "~> 3.0.1"},
      {:spandex_datadog, "~> 1.0.0"},
      {:spandex_ecto, "~> 0.6.2"},
      {:spandex_phoenix, "~> 1.0.0"},
      {:statix, "~> 1.2"},
      {:sweet_xml, "~> 0.6"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_poller, "~> 0.4"},
      {:timex, "~> 3.1"},
      {:x509, "~> 0.5.1 or ~> 0.6"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate",
        "run priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end
end
