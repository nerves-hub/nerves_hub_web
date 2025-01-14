Mimic.copy(NervesHub.Tracker)
Mimic.copy(NervesHub.Firmwares.DeltaUpdater.Default)
Mimic.copy(NervesHub.Firmwares.Upload.File)
Mimic.copy(NervesHub.Firmwares.Upload)

ExUnit.start(capture_log: true, exclude: [:pending])

Ecto.Adapters.SQL.Sandbox.mode(NervesHub.Repo, :manual)
