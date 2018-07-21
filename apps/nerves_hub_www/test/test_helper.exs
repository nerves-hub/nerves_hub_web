opts =
  case System.get_env("CI") do
    nil -> []
    _ -> [exclude: [:ca_integration]]
  end

Logger.remove_backend(:console)
Code.compiler_options(ignore_module_conflict: true)

ExUnit.start(opts)

Ecto.Adapters.SQL.Sandbox.mode(NervesHubCore.Repo, :manual)
