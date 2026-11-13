defmodule NervesHub.Support.ConsoleStandIn do
  @moduledoc """
  Stands in for a device's `NervesHubWeb.ConsoleChannel`: subscribes to the
  device's console topic and answers locates the way the channel does, with no
  device or socket behind it.

  Linked to the caller, so it goes away with the test that started it.
  """

  alias NervesHub.Consoles

  @doc "Start a stand-in console for `device_id`, subscribed before this returns."
  @spec start(integer()) :: pid()
  def start(device_id) do
    caller = self()

    pid =
      spawn_link(fn ->
        :ok = Consoles.PubSub.subscribe_console(device_id)
        send(caller, {:console_stand_in, self()})
        answer()
      end)

    receive do
      {:console_stand_in, ^pid} -> pid
    after
      1000 -> raise "the console stand-in did not subscribe"
    end
  end

  @doc "Go away, as a console channel does when its device disconnects."
  @spec stop(pid()) :: :ok
  def stop(pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      1000 -> raise "the console stand-in did not stop"
    end
  end

  defp answer() do
    receive do
      {:locate_console, from, ref} ->
        send(from, {:console_located, ref, self()})
        answer()

      :stop ->
        :ok

      _other ->
        answer()
    end
  end
end
