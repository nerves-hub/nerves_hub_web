ExUnit.start(exclude: [:ca_integration])

Ecto.Adapters.SQL.Sandbox.mode(NervesHubCore.Repo, :manual)
