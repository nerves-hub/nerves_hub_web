defmodule NervesHub.Stats do
  @moduledoc """
  A module for creating and sending StatsD metrics
  """
  use GenServer

  alias NervesHub.Statix, as: ServerStatix

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_opts) do
    Process.flag(:trap_exit, true)
    host = Application.get_env(:nerves_hub_www, :statsd_host, nil)
    port = Application.get_env(:nerves_hub_www, :statsd_port, nil)

    if host && port do
      :ok = ServerStatix.connect()

      Bark.info(__ENV__,
        key: "stats.init.connected",
        message: "StatsD Server Connected!",
        host: host,
        port: port
      )

      {:ok, :connected}
    else
      Bark.error(__ENV__,
        key: "stats.init.error.unable_to_connect",
        message: "Unable to connect to StatsD Server.",
        host: host,
        port: port
      )

      {:ok, :not_connected}
    end
  end

  def increment(key, val \\ 1, tags \\ []) when is_number(val) do
    GenServer.cast(__MODULE__, {:increment, [key, val, options(tags)]})
  end

  def decrement(key, val \\ 1, tags \\ []) when is_number(val) do
    GenServer.cast(__MODULE__, {:decrement, [key, val, options(tags)]})
  end

  def gauge(key, val, tags \\ []) do
    GenServer.cast(__MODULE__, {:gauge, [key, val, options(tags)]})
  end

  def histogram(key, val, tags \\ []) do
    GenServer.cast(__MODULE__, {:histogram, [key, val, options(tags)]})
  end

  # val is expected in milliseconds
  def timing(key, val, tags \\ []) do
    GenServer.cast(__MODULE__, {:timing, [key, val, options(tags)]})
  end

  def measure(key, tags \\ [], fun) when is_function(fun, 0) do
    GenServer.call(__MODULE__, {:measure, [key, options(tags), fun]})
  end

  def set(key, val, tags \\ []) do
    GenServer.cast(__MODULE__, {:set, [key, val, options(tags)]})
  end

  def handle_info({:EXIT, port, reason}, %Statix.Conn{sock: __MODULE__} = state) do
    Bark.error(__ENV__,
      key: "stats.handle_info.error.port_exited",
      message: "Port exited with reason.",
      port: port,
      reason: reason
    )

    {:stop, :normal, state}
  end

  # This happens when the process is shutdown because it shouldn't be connected to the stats server.
  def handle_info({:EXIT, _pid, :normal}, :not_connected = state) do
    {:stop, :normal, state}
  end

  # Hackney is leaking messages. This handles these messages, so the process doesn't crash.
  # https://github.com/benoitc/hackney/issues/464
  def handle_info({:ssl_closed, {:sslsocket, {:gen_tcp, _, _, _}, _}}, state) do
    {:noreply, [], state}
  end

  def handle_call({:measure, [_, _, f]}, _from, :not_connected = state) do
    {:reply, f.(), state}
  end

  def handle_call({:measure, params}, _from, :connected = state) do
    {:reply, apply(NervesHub.Statix, :measure, params), state}
  end

  def handle_cast(_, :not_connected = state) do
    {:noreply, state}
  end

  def handle_cast({method, params}, :connected = state) do
    apply(NervesHub.Statix, method, params)
    {:noreply, state}
  end

  def options(additional_tags) do
    env = Application.get_env(:nerves_hub_www, :env)

    base_options = [
      tags: [
        "env:#{env}",
        "service:nerves_hub_www",
        "dyno:#{dyno_type()}"
      ]
    ]

    # Handle recieving keyword tuples from other apps
    handle_additional_tags(additional_tags, base_options)
  end

  @doc """
  Format additional tags from other applications together with our base tags in a way that will cause Statix to not error
  ## Examples
      iex> base_options = [prefix: "nerves_hub_www.", tags: ["env:dev", "service:nerves_hub_www"]]
      iex> additional = [{:sample_rate, 1.0}, tags: ["http_status:200", "http_host:smarthome-cahatlas-qa.herokuapp.com", "http_status_family:2xx"]]
      iex> NervesHub.Stats.handle_additional_tags(additional, base_options)
      [
        tags: ["http_status:200", "http_host:smarthome-cahatlas-qa.herokuapp.com",
        "http_status_family:2xx", "env:dev", "service:nerves_hub_www"],
        sample_rate: 1.0,
        prefix: "nerves_hub_www."
      ]
      iex> base_options = [prefix: "nerves_hub_www.", tags: ["env:dev", "service:nerves_hub_www"]]
      iex> additional = []
      iex> NervesHub.Stats.handle_additional_tags(additional, base_options)
      [prefix: "nerves_hub_www.", tags: ["env:dev", "service:nerves_hub_www"]]
  """
  def handle_additional_tags(additional_tags, base_options) do
    Enum.reduce(additional_tags, base_options, fn x, acc ->
      case x do
        {:tags, tag_list} ->
          current_tags = Keyword.get(acc, :tags, [])
          Keyword.put(acc, :tags, tag_list ++ current_tags)

        {key, val} ->
          Keyword.put(acc, key, val)

        val ->
          current_tags = Keyword.get(acc, :tags, [])
          Keyword.put(acc, :tags, [val] ++ current_tags)
      end
    end)
  end

  defp dyno_type do
    Application.get_env(:nerves_hub_www, :dyno, "web")
  end
end

defmodule NervesHub.Statix do
  use Statix
end
