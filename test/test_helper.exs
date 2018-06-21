opts =
  case System.get_env("CI") do
    nil -> []
    _ -> [exclude: [:ca_integration]]
  end

ExUnit.start(opts)

Ecto.Adapters.SQL.Sandbox.mode(NervesHub.Repo, :manual)
