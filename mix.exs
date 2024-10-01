defmodule NervesHub.MixProject do
  use Mix.Project

  def project do
    [
      app: :nerves_hub,
      version: "2.0.0+#{build()}",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: [
        docs: :docs
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.11",
      releases: [
        nerves_hub: [
          steps: [:assemble],
          include_executables_for: [:unix],
          applications: [
            nerves_hub: :permanent
          ]
        ]
      ],
      dialyzer: [
        flags: [:missing_return, :extra_return, :unmatched_returns, :error_handling, :underspecs],
        plt_add_apps: [:ex_unit, :mix]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {NervesHub.Application, []},
      extra_applications: [
        :base62,
        :inets,
        :jason,
        :logger,
        :os_mon,
        :runtime_tools,
        :timex,
        :crypto,
        :public_key
      ]
    ]
  end

  defp build() do
    cmd = "git rev-parse --short=8 HEAD"

    case System.shell(cmd, stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> "dev"
    end
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:mix_test_watch, "~> 1.0", only: :test, runtime: false},
      {:recon, "~> 2.5"},
      {:assert_eventually, "~> 1.0.0", only: [:dev, :test]},
      {:bandit, "~> 1.0"},
      {:base62, "~> 1.2"},
      {:bcrypt_elixir, "~> 3.0"},
      {:castore, "~> 1.0"},
      {:circular_buffer, "~> 0.4.1"},
      {:comeonin, "~> 5.3"},
      {:contex, "~> 0.5.0"},
      {:crontab, "~> 1.1"},
      {:decorator, "~> 1.2"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.8", override: true},
      {:ecto_psql_extras, "~> 0.7"},
      {:ecto_sql, "~> 3.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:finch, "~> 0.19.0"},
      {:floki, ">= 0.27.0", only: :test},
      {:gen_smtp, "~> 1.0"},
      {:gettext, "~> 0.24.0"},
      {:hackney, "~> 1.16"},
      {:hlclock, "~> 1.0"},
      {:jason, "~> 1.2", override: true},
      {:libcluster_postgres, "~> 0.1.2"},
      {:logfmt, "~> 3.3"},
      {:mox, "~> 1.0", only: [:test, :dev]},
      {:nimble_csv, "~> 1.1"},
      {:oban, "~> 2.11"},
      {:phoenix, "~> 1.7.0"},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_html, "~> 3.3.1", override: true},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20.1"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_swoosh, "~> 1.0"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_test, "~> 0.3.0", only: :test, runtime: false},
      {:plug, "~> 1.7"},
      {:postgrex, "~> 0.14"},
      {:scrivener_ecto, "~> 3.0"},
      {:scrivener_html, git: "https://github.com/nerves-hub/scrivener_html", branch: "phx-1.5"},
      {:sentry, "~> 10.0"},
      {:slipstream, "~> 1.0", only: [:test, :dev]},
      {:sweet_xml, "~> 0.6"},
      {:swoosh, "~> 1.12"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_metrics_statsd, "~> 0.7.0"},
      {:telemetry_poller, "~> 1.0"},
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
      "assets.setup": ["assets.install", "assets.build"],
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate",
        "run priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "ecto.migrate.reset": ["ecto.drop", "ecto.create", "ecto.migrate"],
      "ecto.migrate.redo": ["ecto.rollback", "ecto.migrate"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in [:dev, :test],
    do: ["lib", "test/support"]

  defp elixirc_paths(_),
    do: ["lib"]
end
