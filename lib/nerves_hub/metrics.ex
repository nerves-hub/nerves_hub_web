defmodule NervesHub.Metrics do
  use Supervisor

  import Telemetry.Metrics

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    statsd_config = Application.get_env(:nerves_hub, :statsd)

    children = [
      NervesHub.Metrics.Reporters,
      {TelemetryMetricsStatsd,
       host: statsd_config[:host],
       port: statsd_config[:port],
       formatter: :datadog,
       metrics: [
         # NervesHub
         counter("nerves_hub.devices.connect.count", tags: [:env, :service]),
         counter("nerves_hub.devices.disconnect.count", tags: [:env, :service]),
         counter("nerves_hub.devices.duplicate_connection", tags: [:env, :service]),
         counter("nerves_hub.devices.deployment.changed.count", tags: [:env, :service]),
         counter("nerves_hub.devices.deployment.update.manual.count", tags: [:env, :service]),
         counter("nerves_hub.devices.deployment.update.automatic.count", tags: [:env, :service]),
         counter("nerves_hub.devices.deployment.penalty_box.check.count", tags: [:env, :service]),
         counter("nerves_hub.deployments.trigger_update.count", tags: [:env, :service]),
         counter("nerves_hub.deployments.trigger_update.device.count", tags: [:env, :service]),
         counter("nerves_hub.devices.jitp.created.count", tags: [:env, :service]),
         counter("nerves_hub.device_certificates.created.count", tags: [:env, :service]),
         last_value("nerves_hub.devices.online.count", tags: [:env, :service, :node]),
         counter("nerves_hub.rate_limit.accepted.count", tags: [:env, :service]),
         counter("nerves_hub.rate_limit.pruned.count", tags: [:env, :service]),
         counter("nerves_hub.rate_limit.rejected.count", tags: [:env, :service]),
         counter("nerves_hub.ssl.fail.count", tags: [:env, :service]),
         counter("nerves_hub.ssl.success.count", tags: [:env, :service]),
         counter("nerves_hub.tracker.exception.count", tags: [:env, :service]),
         # General
         counter("phoenix.endpoint.start.count", tags: [:env, :service]),
         summary("phoenix.endpoint.stop.duration",
           tags: [:env, :service],
           unit: {:native, :millisecond}
         ),
         summary("phoenix.router_dispatch.stop.duration",
           tags: [:route, :env, :service],
           unit: {:native, :millisecond}
         ),
         counter("nerves_hub.repo.query.count", tags: [:env, :service]),
         distribution("nerves_hub.repo.query.idle_time",
           tags: [:env, :service],
           unit: {:native, :millisecond}
         ),
         distribution("nerves_hub.repo.query.queue_time",
           tags: [:env, :service],
           unit: {:native, :millisecond}
         ),
         distribution("nerves_hub.repo.query.query_time",
           tags: [:env, :service],
           unit: {:native, :millisecond}
         ),
         distribution("nerves_hub.repo.query.decode_time",
           tags: [:env, :service],
           unit: {:native, :millisecond}
         ),
         distribution("nerves_hub.repo.query.total_time",
           tags: [:env, :service],
           unit: {:native, :millisecond}
         ),
         summary("vm.memory.total", tags: [:env, :service], unit: {:byte, :kilobyte}),
         summary("vm.total_run_queue_lengths.total", tags: [:env, :service]),
         summary("vm.total_run_queue_lengths.cpu", tags: [:env, :service]),
         summary("vm.total_run_queue_lengths.io", tags: [:env, :service])
       ],
       global_tags: [
         env: Application.get_env(:nerves_hub, :deploy_env),
         dyno: Application.get_env(:nerves_hub, :app),
         service: "nerves_hub"
       ]},
      {:telemetry_poller,
       measurements: [
         {NervesHub.Metrics, :dispatch_node_count, []},
         {NervesHub.Metrics, :dispatch_device_count, []}
       ],
       period: :timer.seconds(60),
       name: :nerves_hub_poller}
    ]

    Supervisor.init(children, strategy: :one_for_one)
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

defmodule NervesHub.Metrics.Reporters do
  @moduledoc """
  GenServer to hook up telemetry events on boot

  Attaches reporters after initialization
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def init(_) do
    {:ok, %{}, {:continue, :initialize}}
  end

  def handle_continue(:initialize, state) do
    reporters = [
      NervesHub.EctoReporter,
      NervesHub.DeviceReporter,
      NervesHub.NodeReporter
    ]

    Enum.each(reporters, fn reporter ->
      :telemetry.attach_many(reporter, reporter.events(), &reporter.handle_event/4, [])
    end)

    {:noreply, state}
  end
end

defmodule NervesHub.EctoReporter do
  require Logger

  def events() do
    [
      [:nerves_hub, :repo, :query]
    ]
  end

  def handle_event([:nerves_hub, :repo, :query], %{queue_time: queue_time}, _, _) do
    queue_time = :erlang.convert_time_unit(queue_time, :native, :millisecond)

    if queue_time > 500 do
      Logger.warning("[Ecto] Queuing is at #{queue_time}ms")
    end
  end

  # No queue time
  def handle_event([:nerves_hub, :repo, :query], _, _, _) do
    :ok
  end
end

defmodule NervesHub.DeviceReporter do
  require Logger

  def events() do
    [
      [:nerves_hub, :devices, :connect],
      [:nerves_hub, :devices, :disconnect],
      [:nerves_hub, :devices, :duplicate_connection],
      [:nerves_hub, :devices, :update, :automatic]
    ]
  end

  def handle_event([:nerves_hub, :devices, :connect], _, metadata, _) do
    Logger.info("Device connected",
      event: "nerves_hub.devices.connect",
      identifier: metadata[:identifier],
      firmware_uuid: metadata[:firmware_uuid]
    )
  end

  def handle_event([:nerves_hub, :devices, :duplicate_connection], _, metadata, _) do
    Logger.info("Device duplicate connection detected",
      event: "nerves_hub.devices.duplicate_connection",
      ref_id: metadata[:ref_id],
      identifier: metadata[:device].identifier
    )
  end

  def handle_event([:nerves_hub, :devices, :disconnect], _, metadata, _) do
    Logger.info("Device disconnected",
      event: "nerves_hub.devices.disconnect",
      ref_id: metadata[:ref_id],
      identifier: metadata[:identifier]
    )
  end

  def handle_event([:nerves_hub, :devices, :update, :automatic], _, metadata, _) do
    Logger.info("Device received update",
      event: "nerves_hub.devices.update.automatic",
      ref_id: metadata[:ref_id],
      identifier: metadata[:identifier],
      firmware_uuid: metadata[:firmware_uuid]
    )
  end

  def handle_event([:nerves_hub, :devices, :update, :successful], _, metadata, _) do
    Logger.info("Device updated firmware",
      event: "nerves_hub.devices.update.successful",
      identifier: metadata[:identifier],
      firmware_uuid: metadata[:firmware_uuid]
    )
  end
end

defmodule NervesHub.NodeReporter do
  @moduledoc """
  Report on node events
  """

  require Logger

  def events() do
    [
      [:nerves_hub, :nodes]
    ]
  end

  def handle_event([:nerves_hub, :nodes], %{count: count}, %{nodes: nodes}, _) do
    if Application.get_env(:nerves_hub, NodeReporter)[:enabled] do
      Logger.info("Node count: #{count}; Node list: #{inspect(nodes)}")
    end
  end
end
