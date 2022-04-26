defmodule NervesHubAPI.Mixfile do
  use Mix.Project

  def project do
    [
      app: :nerves_hub_api,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {NervesHubAPI.Application, []},
      extra_applications: [:logger, :runtime_tools, :base62]
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
      {:phoenix, "~> 1.6"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:plug, "~> 1.7"},
      {:plug_cowboy, "~> 2.1"},
      {:gettext, "~> 0.11"},
      {:rollbax, "~> 0.11.0"},
      {:base62, "~> 1.2"},
      {:cowboy, "~> 2.1", override: true},
      {:jason, "~> 1.2", override: true},
      {:nerves_hub_device, in_umbrella: true},
      {:nerves_hub_web_core, in_umbrella: true}
    ]
  end
end
