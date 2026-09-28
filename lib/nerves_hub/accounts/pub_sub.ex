defmodule NervesHub.Accounts.PubSub do
  @moduledoc """
  Tells open sessions on a device that what their user can reach may have
  changed, backed by the `:group` library.

  A console, local shell or device page checks the user's access when it
  opens. These messages ask it to check again, and close if the answer is now
  no. Two things can change the answer:

    * the device's tags, which decide which custom roles see it
      (`NervesHub.Devices.Visibility`), and
    * the user's role: its permissions or tags were edited, the user was given
      another role, or they were removed from the org.

  The message says only that something changed. Each session works out for
  itself whether it still has access, from the database.

  ## Groups

    * `access:device/<id>` - sessions open on that device.
    * `access:user/<id>` - sessions that user has open, on any device.

  Membership exists only while a session is open, which is the sparse case
  `:group` is for (see `docs/cross_node_messaging.md`). Both use the default
  cluster.
  """

  @group NervesHub.Group

  @doc """
  Join the calling process to the groups for `user_id` and `device_id`.

  It receives `:access_changed` when either changes. Membership ends when the
  process does.
  """
  @spec subscribe_access(pos_integer(), pos_integer()) :: :ok
  def subscribe_access(user_id, device_id) do
    :ok = Group.join(@group, user_key(user_id), %{})
    :ok = Group.join(@group, device_key(device_id), %{})
  end

  @doc """
  Tell every session open on the device that its tags changed.
  """
  @spec broadcast_device_access_changed(pos_integer()) :: :ok
  def broadcast_device_access_changed(device_id) do
    Group.dispatch(@group, device_key(device_id), :access_changed)
  end

  @doc """
  Tell every session these users have open that their role changed.
  """
  @spec broadcast_users_access_changed([pos_integer()]) :: :ok
  def broadcast_users_access_changed(user_ids) do
    Enum.each(user_ids, &Group.dispatch(@group, user_key(&1), :access_changed))
  end

  defp user_key(user_id), do: "access:user/#{user_id}"
  defp device_key(device_id), do: "access:device/#{device_id}"
end
