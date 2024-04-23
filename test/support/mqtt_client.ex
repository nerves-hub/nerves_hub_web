defmodule NervesHub.Support.MQTTClient do
  @moduledoc """
  Sample MQTT Client for testing device connections
  """
  use Tortoise311.Handler

  import ExUnit.Assertions

  def assert_message(conn, topic, msg) do
    assert Process.alive?(conn)
    assert_receive {:message, ^topic, ^msg}
  end

  def connected?(conn) do
    Process.alive?(conn) and :sys.get_state(conn).status == :up
  end

  def subscribed?(conn, topic) do
    Process.alive?(conn) and
      Enum.find_value(GenServer.call(conn, :subscriptions), fn
        {^topic, _qos} -> true
        _ -> false
      end)
  end

  def start_link(device) do
    opts = [
      client_id: device.identifier,
      server: {Tortoise311.Transport.Tcp, host: "localhost", port: 1883},
      handler: {__MODULE__, [{device, self()}]},
      subscriptions: [{"nh/#{device.identifier}", 0}]
      # will: something?
    ]

    Tortoise311.Connection.start_link(opts)
  end

  @impl Tortoise311.Handler
  def init([{device, test_pid}]) do
    {:ok, %{device: device, test_pid: test_pid}}
  end

  @impl Tortoise311.Handler
  def handle_message(topic_levels, payload, state) do
    send(state.test_pid, {:message, Path.join(topic_levels), payload})
    {:ok, state}
  end
end
