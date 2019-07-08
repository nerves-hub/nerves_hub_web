defmodule NervesHubDevice.Mixfile do
  use Mix.Project

  def project do
    [
      app: :nerves_hub_device,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
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
      mod: {NervesHubDevice.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", Path.expand("../../test/support")]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.4"},
      {:phoenix_pubsub, "~> 1.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:plug, "~> 1.7"},
      {:plug_cowboy, "~> 2.0"},
      {:cowboy, "~> 2.0", override: true},
      {:jason, "~> 1.0"},
      {:gettext, "~> 0.11"},
      {:distillery, "~> 2.0"},
      {:rollbax, "~> 0.10.0"},
      {:phoenix_client, "~> 0.7", only: :test},
      {:websocket_client, "~> 1.3", only: :test},
      {:nerves_hub_web_core, in_umbrella: true}
    ]
  end
end
