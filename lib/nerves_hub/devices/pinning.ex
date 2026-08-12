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
  alias NervesHub.Repo

  @spec get_pinned_devices(Scope.t()) :: [Device.t()]
  def get_pinned_devices(%Scope{user: user}) when not is_nil(user) do
    query =
      PinnedDevice
      |> where(user_id: ^user.id)
      |> select([:device_id])

    Device
    |> where([d], d.id in subquery(query))
    |> join(:left, [d], o in assoc(d, :org))
    |> join(:left, [d, o], p in assoc(d, :product))
    |> join(:left, [d, o, lc], lc in assoc(d, :latest_connection))
    |> join(:left, [d, o, lc, lh], lh in assoc(d, :latest_health))
    |> preload([d, o, p, lc, lh], org: o, product: p, latest_connection: lc, latest_health: lh)
    |> Repo.all()
  end

  @spec pin_device(non_neg_integer(), non_neg_integer()) ::
          {:ok, PinnedDevice.t()} | {:error, Ecto.Changeset.t()}
  def pin_device(user_id, device_id) do
    %{user_id: user_id, device_id: device_id}
    |> PinnedDevice.create()
    |> Repo.insert()
  end

  @spec unpin_device(neg_integer(), non_neg_integer()) ::
          {:ok, PinnedDevice.t()} | {:error, Ecto.Changeset.t()}
  def unpin_device(user_id, device_id) do
    PinnedDevice
    |> Repo.get_by!(user_id: user_id, device_id: device_id)
    |> Repo.delete()
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
