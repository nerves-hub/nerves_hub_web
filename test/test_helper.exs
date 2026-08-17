# The ESP-IDF and AtomVM update tools are off by default
# (ESP_IDF_FIRMWARE_ENABLED, ATOMVM_FIRMWARE_ENABLED); the suite exercises both,
# so enable them here. This has to be `put_env` rather than a line in
# config/test.exs, because config/runtime.exs runs afterwards in every
# environment and would set them straight back to false.
Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, true)
Application.put_env(:nerves_hub, :atomvm_firmware_enabled, true)

Mimic.copy(Ecto.UUID)
Mimic.copy(ProcessHub)
Mimic.copy(ProcessHub.Future)
Mimic.copy(ProcessHub.StartResult)
Mimic.copy(ProcessHub.Future)
Mimic.copy(NervesHub.Devices)
Mimic.copy(NervesHub.Devices.Updates)
Mimic.copy(NervesHub.ManagedDeployments.Distributed.Orchestrator)
Mimic.copy(NervesHub.Firmwares)
Mimic.copy(NervesHub.Firmwares.UpdateTool.Fwup)
Mimic.copy(NervesHub.Uploads)
Mimic.copy(NervesHub.Firmwares.Upload.File)
Mimic.copy(NervesHub.Firmwares.Upload)
Mimic.copy(NervesHub.ManagedDeployments)
Mimic.copy(NervesHub.ManagedDeployments.Distributed.OrchestratorRegistration)
Mimic.copy(NervesHub.Tracker)
Mimic.copy(NervesHub.Scripts.Runner)
Mimic.copy(NervesHub.DeviceLink)
Mimic.copy(NervesHub.DeploymentOrchestratorEvents)
Mimic.copy(NervesHub.Workers.FirmwareDeltaBuilder)
Mimic.copy(NervesHub.RateLimit.LogLines)
Mimic.copy(NervesHub.Devices.LogLines)
Mimic.copy(NervesHub.Devices.Connections)
Mimic.copy(Oban)
Mimic.copy(Sentry)
Mimic.copy(NervesHub.Devices.Pinning)
Mimic.copy(NervesHub.Helpers.Logging)
Mimic.copy(NervesHub.Devices.BulkActions)
Mimic.copy(NervesHub.Archives)
Mimic.copy(NervesHub.Accounts)
Mimic.copy(NervesHub.Products)
Mimic.copy(NervesHub.Devices.Deployments)
Mimic.copy(NervesHub.Devices.CACertificates)
Mimic.copy(:telemetry)
Mimic.copy(System)
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
