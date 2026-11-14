defmodule NervesHub.Accounts.PubSub do
  @moduledoc """
  Tells whatever a member has open in an org that their membership changed.

  A member's role is read when a page mounts, and when a console, local shell
  or device event stream joins, and nothing reads it again on its own. So
  `NervesHub.Accounts.change_org_user_role/2`,
  `NervesHub.Accounts.soft_delete_org_user/1` and
  `NervesHub.Accounts.OrgRoles.update_org_role/2` (to every member holding the
  custom role) publish here once the change is saved, and each subscriber checks the membership again: a page mounts again
  under the new role, and a channel the member may no longer open closes.

  A device's tags decide which custom roles see it (`NervesHub.Devices.Visibility`),
  so a change to them is published here too, to whatever is open on that
  device: consoles, local shells, device event streams and the device's page.

  The message says only that the membership changed, never what to. Each
  subscriber reads it from the database, so a message that arrives late or
  twice does no harm.

  ## Transport: `Phoenix.PubSub`

  Subscribers exist only while something is open, which is the sparse
  membership `:group` is usually for, but the traffic isn't: a membership
  changes when an admin changes it. Every org page subscribes, so `:group`
  would replicate a join and a leave across the cluster on every page load, to
  target a message sent a few times a day. A `Phoenix.PubSub` subscribe is
  node-local and costs nothing to hold, and a broadcast reaching every node is
  cheap at this rate. See `docs/cross_node_messaging.md`.

  Tag changes go to the device instead, on a `:group` key
  (`access:device/<id>`) only processes open on that device join. Those are
  few, but tags change far more often than memberships do, so a cluster-wide
  broadcast for each would be wasted on every other node.
  """

  @group NervesHub.Group

  @doc """
  Subscribe the calling process to changes in `user_id`'s membership of `org_id`.

  It receives `{:org_membership_changed, org_id}`.
  """
  @spec subscribe_membership(pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def subscribe_membership(org_id, user_id) do
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic(org_id, user_id))
  end

  @doc """
  Tell everything `user_id` has open in `org_id` that their membership changed.

  Call it only once the change is committed. Subscribers check the membership
  straight away, and inside the transaction they would still find the old one.
  """
  @spec broadcast_membership_changed(pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def broadcast_membership_changed(org_id, user_id) do
    Phoenix.PubSub.broadcast(NervesHub.PubSub, topic(org_id, user_id), {:org_membership_changed, org_id})
  end

  @doc """
  Join the calling process to changes in `device_id`'s tags.

  It receives `{:device_access_changed, device_id}`. Membership ends when the
  process does.
  """
  @spec subscribe_device_access(pos_integer()) :: :ok
  def subscribe_device_access(device_id) do
    Group.join(@group, device_key(device_id), %{})
  end

  @doc """
  Tell everything open on `device_id` that its tags changed.

  Call it only once the change is committed, for the same reason as
  `broadcast_membership_changed/2`.
  """
  @spec broadcast_device_access_changed(pos_integer()) :: :ok
  def broadcast_device_access_changed(device_id) do
    Group.dispatch(@group, device_key(device_id), {:device_access_changed, device_id})
  end

  defp topic(org_id, user_id), do: "org_membership:#{org_id}:#{user_id}"
  defp device_key(device_id), do: "access:device/#{device_id}"
end
