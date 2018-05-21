defmodule BeamwareClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :beamware_client,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BeamwareClient.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_channel_client, github: "mobileoverlord/phoenix_channel_client"},
      {:websocket_client, "~> 1.3"},
      {:jason, "~> 1.0"}
    ]
  end
end
