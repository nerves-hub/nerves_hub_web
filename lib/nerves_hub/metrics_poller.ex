defmodule NervesHub.MetricsPoller do
  def child_spec() do
    {:telemetry_poller,
     measurements: [
       {NervesHub.MetricsPoller, :dispatch_node_count, []},
       {NervesHub.MetricsPoller, :dispatch_device_count, []}
     ],
     period: :timer.seconds(60),
     name: :nerves_hub_poller}
  end

  def dispatch_node_count() do
    nodes = Node.list()
    :telemetry.execute([:nerves_hub, :nodes], %{count: Enum.count(nodes)}, %{nodes: nodes})
  end

  def dispatch_device_count() do
    device_count = Registry.count(NervesHub.Devices.Registry)
    :telemetry.execute([:nerves_hub, :devices, :online], %{count: device_count}, %{node: node()})
  end
end
