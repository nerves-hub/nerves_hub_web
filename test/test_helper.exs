Logger.remove_backend(:console)

ExUnit.start(exclude: [:pending])

Ecto.Adapters.SQL.Sandbox.mode(NervesHub.Repo, :manual)
