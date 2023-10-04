defmodule NervesHub.Metrics do
  use Supervisor

  import Telemetry.Metrics

  alias NervesHub.Config

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    vapor_config = Vapor.load!(Config)
    statsd_config = vapor_config.statsd

    children = [
      NervesHub.Metrics.Reporters,
      {TelemetryMetricsStatsd,
       host: statsd_config.host,
       port: statsd_config.port,
       formatter: :datadog,
       metrics: [
         # NervesHub
         counter("nerves_hub.devices.connect.count", tags: [:env, :service]),
         counter("nerves_hub.devices.disconnect.count", tags: [:env, :service]),
         counter("nerves_hub.devices.deployment.changed.count", tags: [:env, :service]),
         counter("nerves_hub.devices.deployment.update.manual.count", tags: [:env, :service]),
         counter("nerves_hub.devices.deployment.update.automatic.count", tags: [:env, :service]),
         counter("nerves_hub.devices.deployment.penalty_box.check.count", tags: [:env, :service]),
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
    device_count = Registry.count(NervesHub.Devices)
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
    Logger.info("Node count: #{count}; Node list: #{inspect(nodes)}")
  end
end
