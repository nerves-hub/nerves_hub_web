ExUnit.start(capture_log: true, exclude: [:pending])

Ecto.Adapters.SQL.Sandbox.mode(NervesHub.Repo, :manual)
