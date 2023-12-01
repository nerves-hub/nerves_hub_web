defmodule NervesHub.MixProject do
  use Mix.Project

  def project do
    [
      app: :nerves_hub,
      version: "0.1.0",
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
          reboot_system_after_config: true,
          applications: [
            nerves_hub: :permanent,
            opentelemetry_exporter: :permanent,
            opentelemetry: :temporary
          ]
        ]
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
        :runtime_tools,
        :timex,
        :tls_certificate_check
      ]
    ]
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
      {:bandit, "~> 1.0"},
      {:base62, "~> 1.2"},
      {:bcrypt_elixir, "~> 3.0"},
      # {:dns_cluster, "~> 0.1.1"},
      {:dns_cluster,
       git: "https://github.com/davydog187/dns_cluster.git", branch: "support-multiple-queries"},
      {:castore, "~> 1.0"},
      {:circular_buffer, "~> 0.4.1"},
      {:comeonin, "~> 5.3"},
      {:crontab, "~> 1.1"},
      {:decorator, "~> 1.2"},
      {:ecto, "~> 3.8", override: true},
      {:ecto_sql, "~> 3.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:finch, "~> 0.16.0"},
      {:floki, ">= 0.27.0", only: :test},
      {:gen_smtp, "~> 1.0"},
      {:gettext, "~> 0.23.1"},
      {:hackney, "~> 1.16"},
      {:hlclock, "~> 1.0"},
      {:jason, "~> 1.2", override: true},
      {:logfmt, "~> 3.3"},
      {:mox, "~> 1.0", only: [:test, :dev]},
      {:nimble_csv, "~> 1.1"},
      {:oban, "~> 2.11"},
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_api, "~> 1.2"},
      {:opentelemetry_exporter, "~> 1.4"},
      {:phoenix, "~> 1.7.0"},
      {:phoenix_active_link, "~> 0.3.1"},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_html, "~> 3.3.1", override: true},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20.1"},
      {:phoenix_markdown, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_swoosh, "~> 1.0"},
      {:phoenix_view, "~> 2.0"},
      {:plug, "~> 1.7"},
      {:postgrex, "~> 0.14"},
      {:scrivener_ecto, "~> 2.7"},
      {:scrivener_html, git: "https://github.com/nerves-hub/scrivener_html", branch: "phx-1.5"},
      {:sentry, "~> 10.0"},
      {:slipstream, "~> 1.0", only: [:test, :dev]},
      {:socket_drano, "~> 0.5.0"},
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
