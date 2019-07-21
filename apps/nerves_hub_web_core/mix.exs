defmodule NervesHubWebCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :nerves_hub_web_core,
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
  defp elixirc_paths(env) when env in [:dev, :test],
    do: ["lib", "test/support", Path.expand("../../test/support")]

  defp elixirc_paths(_),
    do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {NervesHubWebCore.Application, []},
      extra_applications: [:logger, :jason]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.4"},
      {:plug, "~> 1.7"},
      {:plug_cowboy, "~> 2.0"},
      {:ecto_sql, "~> 3.0"},
      {:ecto_enum, "~> 1.2"},
      {:postgrex, "~> 0.14"},
      {:bcrypt_elixir, "~> 1.0"},
      {:comeonin, "~> 4.1"},
      {:quantum, "~> 2.3"},
      {:timex, "~> 3.1"},
      {:jason, "~> 1.0"},
      {:sweet_xml, "~> 0.6"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:x509, "~> 0.5.1 or ~> 0.6"}
    ]
  end
end
