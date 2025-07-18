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
        docs: :docs,
        coveralls: :test,
        "coveralls.html": :test
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.18.0",
      releases: [
        nerves_hub: [
          steps: [:assemble],
          include_executables_for: [:unix],
          applications: [
            opentelemetry_exporter: :permanent,
            opentelemetry: :temporary,
            nerves_hub: :permanent
          ]
        ]
      ],
      compilers: compilers(System.get_env("MIX_UNUSED")) ++ Mix.compilers(),
      dialyzer: [
        flags: [:missing_return, :extra_return, :unmatched_returns, :error_handling, :underspecs],
        plt_add_apps: [:ex_unit, :mix],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {NervesHub.Application, []},
      extra_applications: [
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
      {:bcrypt_elixir, "~> 3.0"},
      {:castore, "~> 1.0"},
      {:circular_buffer, "~> 1.0.0"},
      {:comeonin, "~> 5.3"},
      {:confuse, "~> 0.1.5"},
      {:contex, "~> 0.5.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:crontab, "~> 1.1"},
      {:decorator, "~> 1.2"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.8", override: true},
      {:ecto_ch, "~> 0.8.0"},
      {:ecto_psql_extras, "~> 0.7"},
      {:ecto_sql, "~> 3.0"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:excoveralls, "~> 0.18", only: :test},
      {:finch, "~> 0.20.0"},
      {:floki, ">= 0.27.0", only: :test},
      {:gen_smtp, "~> 1.0"},
      {:gettext, "~> 0.26.2"},
      {:hackney, "~> 1.16"},
      {:hammer, "~> 7.0.0"},
      {:hlclock, "~> 1.0"},
      {:process_hub, "~> 0.3.1-alpha"},
      {:jason, "~> 1.2", override: true},
      {:libcluster_postgres, "~> 0.2.0"},
      {:logfmt_ex, "~> 0.4"},
      {:mimic, "~> 2.0", only: [:test, :dev]},
      {:mix_unused, "~> 0.4.1", only: [:dev]},
      {:mjml_eex, "~> 0.12.0"},
      {:nimble_csv, "~> 1.1"},
      {:number, "~> 1.0.5"},
      {:oban, "~> 2.11"},
      {:oban_web, "~> 2.11"},
      {:open_api_spex, "~> 3.21"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_phoenix, "~> 2.0.0-rc.1 "},
      {:opentelemetry_oban, "~> 1.0",
       git: "https://github.com/joshk/opentelemetry-erlang-contrib",
       branch: "update-obans-semantic-conventions",
       subdir: "instrumentation/opentelemetry_oban"},
      {:opentelemetry_bandit, "~> 0.2.0-rc.1"},
      {:open_telemetry_decorator, "~> 1.5"},
      {:phoenix, "~> 1.7.0"},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_html, "~> 3.3.1", override: true},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_test, "~> 0.5", only: :test, runtime: false},
      {:plug, "~> 1.7"},
      {:postgrex, "~> 0.14"},
      {:sentry, "~> 10.0"},
      {:slipstream, "~> 1.0", only: [:test, :dev]},
      {:spellweaver, "~> 0.1", only: [:test, :dev], runtime: false},
      {:sweet_xml, "~> 0.6"},
      {:swoosh, "~> 1.12"},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_metrics_statsd, "~> 0.7.0"},
      {:telemetry_poller, "~> 1.0"},
      {:timex, "~> 3.1"},
      {:ueberauth_google, "~> 0.12"},
      {:unzip, "~> 0.12"},
      {:uuidv7, "~> 1.0"},
      {:x509, "~> 0.5.1 or ~> 0.6"},
      {:flop, "~> 0.26.1"}
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
      "assets.deploy": ["esbuild default --minify", "tailwind default --minify", "phx.digest"],
      "assets.setup": ["assets.install", "assets.build"],
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate",
        "run priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "ecto.migrate.reset": ["ecto.drop", "ecto.create", "ecto.migrate"],
      "ecto.migrate.redo": ["ecto.rollback", "ecto.migrate"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"],
      # Runs most of the non-test CI checks for you
      check: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "deps.unlock --check-unused",
        "dialyzer --format github --format dialyxir",
        "spellweaver.check"
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in [:dev, :test],
    do: ["lib", "test/support"]

  defp elixirc_paths(_),
    do: ["lib"]

  defp compilers(mix_unused) when not is_nil(mix_unused), do: [:unused]
  defp compilers(_), do: []
end
