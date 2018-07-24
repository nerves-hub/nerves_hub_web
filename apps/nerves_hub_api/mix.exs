defmodule NervesHubAPI.Mixfile do
  use Mix.Project

  def project do
    [
      app: :nerves_hub_api,
      version: "0.0.1",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.4",
      elixirc_paths: elixirc_paths(Mix.env),
      compilers: [:phoenix, :gettext] ++ Mix.compilers,
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {NervesHubAPI.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, github: "mobileoverlord/phoenix", branch: "ws_extra_params", override: true},
      {:phoenix_pubsub, "~> 1.0"},
      {:phoenix_live_reload,
       github: "mobileoverlord/phoenix_live_reload",
       branch: "transport",
       override: true,
       only: :dev},
      {:gettext, "~> 0.11"},
      {:cowboy, "~> 2.1", override: true},
      {:nerves_hub_core, in_umbrella: true}
    ]
  end
end
