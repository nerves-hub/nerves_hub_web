defmodule NervesHub.MetricsPoller do
  def child_spec() do
    {:telemetry_poller,
     measurements: [
       {NervesHub.MetricsPoller, :report_device_count, []}
     ],
     period: to_timeout(second: 60),
     name: :nerves_hub_poller}
  end

  def report_device_count() do
    # an ugly way to get the connected device count for a node
    # (we can't use the device registry because it's been removed)
    device_count =
      Enum.count(Process.list(), fn p ->
        Process.info(p)[:dictionary][:"$initial_call"] == {NervesHubWeb.DeviceChannel, :join, 3}
      end)

    :telemetry.execute([:nerves_hub, :devices, :online], %{count: device_count}, %{node: node()})
  end
end
