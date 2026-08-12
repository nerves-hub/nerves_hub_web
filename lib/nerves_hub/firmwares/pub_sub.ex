defmodule NervesHub.Firmwares.PubSub do
  @moduledoc """
  Targeted pub/sub for firmware delta build status, backed by the `:group`
  library.

  This replaces the `Phoenix.PubSub` broadcast on the `"firmware:<id>"` topic.
  The only consumer is the deployment group Show LiveView's summary tab, and
  only for the single firmware that is the current release's delta target — so
  a delta status change was previously fanned out to every node in the cluster
  for at most one web node to use. `Group.dispatch/3` only delivers to nodes
  that have a process joined for the key.

  Events are delivered as `%Phoenix.Socket.Broadcast{}` structs whose `topic` is
  preserved as `"firmware:<id>"`, because the receiver pattern-matches on it
  (`%Broadcast{topic: "firmware:" <> _}`), so only the subscribe/broadcast call
  sites move here.

  ## Membership follows a moving target

  Unlike the other groups in this migration, the subscriber's key changes while
  the process lives: the summary tab follows the deployment group's current
  release, which moves when a new release is activated. Callers must therefore
  leave the previous target — process-death cleanup alone would let memberships
  accumulate for the lifetime of the LiveView, and `:group` membership is
  replicated to every node, unlike a local `Phoenix.PubSub` subscription. See
  `NervesHubWeb.Components.DeploymentGroupPage.Summary`.

  Default `:group` cluster, so a delta status published by the build worker
  reaches the LiveView regardless of which node role ran the build.
  """

  alias NervesHub.Firmwares.FirmwareDelta
  alias Phoenix.Socket.Broadcast

  @group NervesHub.Group

  @doc """
  Join the calling process to a target firmware's delta status group.

  `target_id` is the id of the firmware the deltas are built *towards*.
  """
  @spec subscribe_delta_target(target_id :: integer()) :: :ok
  def subscribe_delta_target(target_id) do
    Group.join(@group, key(target_id), %{})
  end

  @doc """
  Leave a target firmware's delta status group.

  Leaving a group the caller never joined is not an error.
  """
  @spec unsubscribe_delta_target(target_id :: integer()) :: :ok
  def unsubscribe_delta_target(target_id) do
    case Group.leave(@group, key(target_id)) do
      :ok -> :ok
      {:error, :not_in_group} -> :ok
    end
  end

  @doc """
  Dispatch a delta's current build status to every process joined to its target
  firmware's group.

  Returns `:ok` even when no process has joined — a delta built while nobody has
  the deployment group open is the common case and is not an error.
  """
  @spec broadcast_delta_status(FirmwareDelta.t()) :: :ok
  def broadcast_delta_status(%FirmwareDelta{} = firmware_delta) do
    message = %Broadcast{
      topic: topic(firmware_delta.target_id),
      event: "delta/status_update",
      payload: %{
        delta_id: firmware_delta.id,
        source_firmware_id: firmware_delta.source_id,
        status: firmware_delta.status
      }
    }

    Group.dispatch(@group, key(firmware_delta.target_id), message)
  end

  # Group key. "/" is Group's hierarchy separator.
  defp key(target_id), do: "firmware/#{target_id}"

  # Preserved as the previous `Phoenix.PubSub` topic string; the receiver matches
  # on the `"firmware:" <> _` prefix.
  defp topic(target_id), do: "firmware:#{target_id}"
end
