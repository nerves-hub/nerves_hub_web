defmodule NervesHub.Extensions.LocalShellTest do
  use ExUnit.Case, async: true

  alias NervesHub.Consoles
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Extensions.LocalShell
  alias NervesHub.Extensions.State

  defp state(device_id) do
    State.new(%DeviceInfo{device_id: device_id, org_id: 1, product_id: 1})
  end

  defp device_id(), do: System.unique_integer([:positive])

  describe "attach/1" do
    # `Group.join/4` joins the calling process, and the process that has to be a
    # member is the one holding the device's connection. Those are the same
    # process only when `NervesHub.DeviceLink` runs in the connection's own
    # process; where it is reached over `:erpc` they are on different nodes, and
    # joining here would bind the membership to a transient RPC handler that
    # exits as soon as the call returns.
    test "asks the connection to join rather than joining itself" do
      id = device_id()

      {_state, effects} = LocalShell.attach(state(id))

      assert {:group_join, Consoles.PubSub.local_shell_key(id)} in effects
      refute Consoles.PubSub.local_shell_active?(id)
    end

    test "still asks the device for a shell and clears the scrollback" do
      {_state, effects} = LocalShell.attach(state(device_id()))

      assert {:push, "local_shell:request_shell", %{}} in effects
      assert {:scrollback_clear} in effects
    end
  end

  describe "detach/1" do
    test "asks the connection to leave" do
      id = device_id()

      {_state, effects} = LocalShell.detach(state(id))

      assert {:group_leave, Consoles.PubSub.local_shell_key(id)} in effects
      assert {:scrollback_clear} in effects
    end
  end
end
