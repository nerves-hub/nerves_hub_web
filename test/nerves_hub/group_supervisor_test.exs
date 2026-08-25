defmodule NervesHub.GroupSupervisorTest do
  @moduledoc """
  The `:group` tree and the state that does not outlive it.

  Worth testing despite being only a supervisor spec: every failure here is
  silent. Under `:one_for_one` a `Group` restart leaves the "web" cluster
  disconnected and the members non-members, and nothing raises until the next
  `Group.join/4` — or, for `Group.dispatch/4`, never.
  """

  use ExUnit.Case, async: false

  alias NervesHub.CLISessionCache
  alias NervesHub.GroupClusterConnection
  alias NervesHub.GroupSupervisor
  alias NervesHubWeb.RateLimitPubSub

  defp child_ids(children), do: Enum.map(children, & &1.id)

  test "Group starts first and the web cluster state restarts with it" do
    assert {:ok, {flags, children}} = GroupSupervisor.init([])

    # `:rest_for_one` is the fix: anything after Group restarts when it does.
    assert %{strategy: :rest_for_one} = flags

    # Order is load-bearing — the connection must be re-established before the
    # members re-join the cluster it opens.
    assert [
             {Group, NervesHub.Group},
             GroupClusterConnection,
             CLISessionCache,
             RateLimitPubSub
           ] == child_ids(children)
  end

  test "device nodes run neither web-cluster member" do
    previous = Application.fetch_env(:nerves_hub, :app)
    Application.put_env(:nerves_hub, :app, "device")

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:nerves_hub, :app, value)
        :error -> Application.delete_env(:nerves_hub, :app)
      end
    end)

    assert {:ok, {_flags, children}} = GroupSupervisor.init([])

    assert [{Group, NervesHub.Group}, GroupClusterConnection] == child_ids(children)
  end

  test "the running tree is connected to the web cluster" do
    assert Group.connected?(NervesHub.Group, "web")

    running =
      GroupSupervisor
      |> Supervisor.which_children()
      |> Enum.map(fn {id, pid, _type, _mods} -> {id, is_pid(pid)} end)

    assert {GroupClusterConnection, true} in running
    assert {CLISessionCache, true} in running
    assert {RateLimitPubSub, true} in running
  end
end
