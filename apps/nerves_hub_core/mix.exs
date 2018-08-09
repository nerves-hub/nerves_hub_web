defmodule NervesHubCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :nerves_hub_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
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

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", "../../test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {NervesHubCore.Application, []},
      extra_applications: [:logger, :jason]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 2.2"},
      {:postgrex, "~> 0.13"},
      {:bcrypt_elixir, "~> 1.0"},
      {:comeonin, "~> 4.1"},
      # poison can be removed once a new release of postgrex is made
      {:poison, "~> 3.0"},
      {:timex, "~> 3.1"},
      {:plug, "~> 1.6"},
      {:jason, "~> 1.0"},
      {:phoenix, github: "mobileoverlord/phoenix", branch: "ws_extra_params", override: true},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"}
    ]
  end
end
