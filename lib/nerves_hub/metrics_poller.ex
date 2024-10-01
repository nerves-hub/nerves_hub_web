defmodule NervesHub.MetricsPoller do
  def child_spec() do
    {:telemetry_poller,
     measurements: [
       {NervesHub.MetricsPoller, :report_device_count, []}
     ],
     period: :timer.seconds(60),
     name: :nerves_hub_poller}
  end

  def report_device_count() do
    device_count = Registry.count(NervesHub.Devices.Registry)
    :telemetry.execute([:nerves_hub, :devices, :online], %{count: device_count}, %{node: node()})
  end
end
