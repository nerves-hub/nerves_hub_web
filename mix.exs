defmodule NervesHub.Mixfile do
  use Mix.Project

  def project do
    [
      app: :nerveshub,
      version: "0.0.1",
      elixir: "~> 1.4",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
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

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {NervesHub.Application, []},
      extra_applications: [
        :logger,
        :runtime_tools,
        :timex
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 1.0"},
      {:comeonin, "~> 4.1"},
      {:jason, "~> 1.0"},
      # poison can be removed once a new release of postgrex is made
      {:poison, "~> 3.0"},
      {:plug, github: "mobileoverlord/plug", branch: "client_ssl", override: true},
      {:phoenix, github: "mobileoverlord/phoenix", branch: "ws_extra_params", override: true},
      {:phoenix_pubsub, "~> 1.0"},
      {:phoenix_ecto, github: "phoenixframework/phoenix_ecto"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 2.10"},
      {:phoenix_live_reload,
       github: "mobileoverlord/phoenix_live_reload",
       branch: "transport",
       override: true,
       only: :dev},
      {:gettext, "~> 0.11"},
      {:cowboy, "~> 2.0", override: true},
      {:swoosh, "~> 0.13"},
      {:timex, "~> 3.1"},
      {:phoenix_swoosh, "~> 0.2"},
      {:nerveshub_client, path: "client", only: :test},
      {:excoveralls, "~> 0.8", only: :test}
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
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end
end
