defmodule NervesHubUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      version: "0.1.0",
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: [],
        ignore_warnings: "dialyzer.ignore-warnings"
      ],
      releases: [
        nerves_hub_www: [
          steps: [:assemble],
          include_executables_for: [:unix],
          runtime_config_path: "apps/nerves_hub_www/config/release.exs",
          reboot_system_after_config: true,
          applications: [
            nerves_hub_www: :permanent
          ]
        ],
        nerves_hub_device: [
          steps: [:assemble],
          include_executables_for: [:unix],
          runtime_config_path: "apps/nerves_hub_device/config/release.exs",
          reboot_system_after_config: true,
          applications: [
            nerves_hub_device: :permanent
          ]
        ],
        nerves_hub_api: [
          steps: [:assemble],
          include_executables_for: [:unix],
          runtime_config_path: "apps/nerves_hub_api/config/release.exs",
          reboot_system_after_config: true,
          applications: [
            nerves_hub_api: :permanent
          ]
        ]
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
      # {:excoveralls, "~> 0.8", only: :test},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: :test, runtime: false}
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
        "run apps/nerves_hub_web_core/priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in [:dev, :test],
    do: [Path.expand("test/support")]

  defp elixirc_paths(_),
    do: ["lib"]
end
