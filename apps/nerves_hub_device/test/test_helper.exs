Logger.remove_backend(:console)

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(NervesHubCore.Repo, :manual)
