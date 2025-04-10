Mimic.copy(ProcessHub)
Mimic.copy(NervesHub.Devices)
Mimic.copy(NervesHub.ManagedDeployments.Distributed.Orchestrator)
Mimic.copy(NervesHub.Firmwares.DeltaUpdater.Default)
Mimic.copy(NervesHub.Firmwares.Upload.File)
Mimic.copy(NervesHub.Firmwares.Upload)
Mimic.copy(NervesHub.Tracker)
Mimic.copy(NervesHub.Scripts.Runner)

ExUnit.start(capture_log: true, exclude: [:pending])

Ecto.Adapters.SQL.Sandbox.mode(NervesHub.Repo, :manual)
