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
  defp elixirc_paths(env) when env in [:dev, :test],
    do: ["lib", "test/support", Path.expand("../../test/support")]

  defp elixirc_paths(_),
    do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.5"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:plug, "~> 1.7"},
      {:gettext, "~> 0.11"},
      {:gen_leader, github: "garret-smith/gen_leader_revival"},
      {:gproc, "~> 0.9.0"},
      {:rollbax, "~> 0.11.0"},
      {:plug_cowboy, "~> 2.1"},
      {:cowboy, "~> 2.0", override: true},
      {:jason, "~> 1.2", override: true},
      {:slipstream, "~> 1.0", only: [:test, :dev]},
      {:nerves_hub_web_core, in_umbrella: true},
      {:logfmt, "~> 3.3"}
    ]
  end
end
