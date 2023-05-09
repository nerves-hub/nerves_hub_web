defmodule NervesHub.Metrics do
  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      NervesHub.Metrics.Reporters,
      {:telemetry_poller,
       measurements: [
         {NervesHub.Metrics, :dispatch_node_count, []}
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
end

defmodule NervesHub.Metrics.Reporters do
  @moduledoc """
  GenServer to hook up telemetry events on boot

  Attaches reporters after initialization
  """

  use GenServer

  alias NervesHub.NodeReporter

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def init(_) do
    {:ok, %{}, {:continue, :initialize}}
  end

  def handle_continue(:initialize, state) do
    reporters = [
      NodeReporter
    ]

    Enum.each(reporters, fn reporter ->
      :telemetry.attach_many(reporter, reporter.events(), &reporter.handle_event/4, [])
    end)

    {:noreply, state}
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
