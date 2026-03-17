Mimic.copy(ProcessHub)
Mimic.copy(ProcessHub.Future)
Mimic.copy(ProcessHub.StartResult)
Mimic.copy(ProcessHub.Future)
Mimic.copy(NervesHub.Devices)
Mimic.copy(NervesHub.ManagedDeployments.Distributed.Orchestrator)
Mimic.copy(NervesHub.Firmwares)
Mimic.copy(NervesHub.Firmwares.UpdateTool.Fwup)
Mimic.copy(NervesHub.Firmwares.Upload.File)
Mimic.copy(NervesHub.Firmwares.Upload)
Mimic.copy(NervesHub.ManagedDeployments)
Mimic.copy(NervesHub.ManagedDeployments.Distributed.OrchestratorRegistration)
Mimic.copy(NervesHub.Tracker)
Mimic.copy(NervesHub.Scripts.Runner)
Mimic.copy(NervesHub.Workers.FirmwareDeltaBuilder)
Mimic.copy(Oban)
Mimic.copy(Sentry)
Mimic.copy(:telemetry)
Mimic.copy(Ueberauth)

[capture_log: true, exclude: [:pending]]
|> then(fn opts ->
  if System.get_env("CI") do
    opts
  else
    Keyword.put(opts, :max_cases, 10)
  end
end)
|> ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(NervesHub.Repo, :manual)
