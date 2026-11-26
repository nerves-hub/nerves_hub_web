defmodule NervesHub.Devices.Pinning do
  @moduledoc """
  Context for pinning devices to a user.

  Pinned devices are surfaced to the user (e.g. on their orgs dashboard)
  independently of the product they belong to.
  """

  import Ecto.Query

  alias NervesHub.Accounts.Scope
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.PinnedDevice
  alias NervesHub.Devices.Visibility
  alias NervesHub.Repo

  @spec get_pinned_devices(Scope.t()) :: [Device.t()]
  def get_pinned_devices(%Scope{user: user}) when not is_nil(user) do
    query =
      PinnedDevice
      |> where(user_id: ^user.id)
      |> select([:device_id])

    # Removing a member or moving a device unpins it, but deleting an org
    # doesn't, so its devices are left out here instead. This also drops a
    # device pinned before the user's role stopped seeing it.
    Device
    |> Visibility.where_visible(user)
    |> where([d], d.id in subquery(query))
    |> join(:inner, [d], o in assoc(d, :org))
    |> where([d, o], is_nil(o.deleted_at))
    |> join(:left, [d, o], p in assoc(d, :product))
    |> join(:left, [d, o, lc], lc in assoc(d, :latest_connection))
    |> join(:left, [d, o, lc, lh], lh in assoc(d, :latest_health))
    |> preload([d, o, p, lc, lh], org: o, product: p, latest_connection: lc, latest_health: lh)
    |> Repo.all()
  end

  @doc """
  Pins the device for the user.

  Pinning an already pinned device changes nothing and returns a pin
  without an `id`.
  """
  @spec pin_device(pos_integer(), pos_integer()) ::
          {:ok, PinnedDevice.t()} | {:error, Ecto.Changeset.t()}
  def pin_device(user_id, device_id) do
    %{user_id: user_id, device_id: device_id}
    |> PinnedDevice.create()
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :device_id])
  end

  @doc """
  Unpins the device for the user.

  Returns `:ok` whether or not the device was pinned.
  """
  @spec unpin_device(pos_integer(), pos_integer()) :: :ok
  def unpin_device(user_id, device_id) do
    {_count, _} =
      PinnedDevice
      |> where(user_id: ^user_id, device_id: ^device_id)
      |> Repo.delete_all()

    :ok
  end

  def device_pinned?(user_id, device_id) do
    PinnedDevice
    |> where([p], p.user_id == ^user_id)
    |> where([p], p.device_id == ^device_id)
    |> Repo.exists?()
  end

  @doc """
  Unpins all devices belonging to user and org.
  """
  @spec unpin_org_devices(non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), nil | [term()]}
  def unpin_org_devices(user_id, org_id) do
    sub =
      Device
      |> where(org_id: ^org_id)
      |> select([:id])

    PinnedDevice
    |> where([p], p.user_id == ^user_id)
    |> where([p], p.device_id in subquery(sub))
    |> Repo.delete_all()
  end
end
