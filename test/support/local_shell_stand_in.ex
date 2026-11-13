defmodule NervesHub.Support.LocalShellStandIn do
  @moduledoc """
  Stands in for a device's extensions channel with the `LocalShell` extension
  attached: subscribes to the device's extensions topic and answers locates the
  way the attached extension does, with no device or socket behind it.

  Linked to the caller, so it goes away with the test that started it.
  """

  alias NervesHub.Extensions
  alias NervesHub.Extensions.LocalShell

  @doc "Start a stand-in shell for `device_id`, subscribed before this returns."
  @spec start(integer()) :: pid()
  def start(device_id) do
    caller = self()

    pid =
      spawn_link(fn ->
        :ok = Extensions.PubSub.subscribe_device(device_id)
        send(caller, {:local_shell_stand_in, self()})
        answer()
      end)

    receive do
      {:local_shell_stand_in, ^pid} -> pid
    after
      1000 -> raise "the local shell stand-in did not subscribe"
    end
  end

  defp answer() do
    receive do
      {LocalShell, {:locate, from, ref}} ->
        send(from, {:local_shell_located, ref})
        answer()

      _other ->
        answer()
    end
  end
end
