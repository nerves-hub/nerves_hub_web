defmodule NervesHub.Devices.Connections do
  @moduledoc """
  Handles connection data for devices, reported from device socket.
  """
  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Repo
  alias NervesHub.Tracker

  @doc """
  Get all connections for a device.
  """
  @spec get_device_connections(non_neg_integer()) :: [DeviceConnection.t()]
  def get_device_connections(device_id) do
    DeviceConnection
    |> where(device_id: ^device_id)
    |> order_by(asc: :last_seen_at)
    |> Repo.all()
  end

  @doc """
  Get device connection information for Orgs.
  """
  @spec get_connection_status_by_orgs(org_ids :: [non_neg_integer()]) :: %{
          non_neg_integer() => %{online: non_neg_integer(), offline: non_neg_integer()}
        }
  def get_connection_status_by_orgs(org_ids) when is_list(org_ids) do
    q =
      DeviceConnection
      |> join(:inner, [d], p in assoc(d, :product))
      |> select([d, p], [p.org_id, count(d.id)])
      |> where([_, p], p.org_id in ^org_ids)
      |> group_by([_, p], p.org_id)

    online =
      q
      |> where([d], d.status == :connected)
      |> Repo.all()

    offline =
      q
      |> where([d], d.status != :connected)
      |> Repo.all()

    for org_id <- org_ids, into: %{} do
      {org_id, %{online: 0, offline: 0}}
    end
    |> to_connection_status(online, :online)
    |> to_connection_status(offline, :offline)
  end

  @doc """
  Get device connection information for Products.
  """
  @spec get_connection_status_by_products(product_ids :: [non_neg_integer()]) :: %{
          non_neg_integer() => %{online: non_neg_integer(), offline: non_neg_integer()}
        }
  def get_connection_status_by_products(product_ids) when is_list(product_ids) do
    q =
      DeviceConnection
      |> join(:inner, [d], p in assoc(d, :product))
      |> select([d, p], [p.id, count(d.id)])
      |> where([_, p], p.id in ^product_ids)
      |> group_by([_, p], p.id)

    online =
      q
      |> where([d], d.status == :connected)
      |> Repo.all()

    offline =
      q
      |> where([d], d.status != :connected)
      |> Repo.all()

    for product_id <- product_ids, into: %{} do
      {product_id, %{online: 0, offline: 0}}
    end
    |> to_connection_status(online, :online)
    |> to_connection_status(offline, :offline)
  end

  defp to_connection_status(start, counts, status) do
    counts
    |> Enum.reduce(start, fn [id, count], acc ->
      current = Map.get(acc, id, %{})
      Map.put(acc, id, Map.put(current, status, count))
    end)
  end

  @doc """
  Get latest inserted connection for a device.
  """
  @spec get_latest_for_device(non_neg_integer()) :: DeviceConnection.t() | nil
  def get_latest_for_device(device_id) do
    DeviceConnection
    |> where(device_id: ^device_id)
    |> order_by(desc: :last_seen_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Creates a device connection, reported from device socket
  """
  @spec device_connecting(Device.t(), non_neg_integer()) ::
          {:ok, DeviceConnection.t()} | {:error, Ecto.Changeset.t()}
  def device_connecting(device, product_id) do
    now = DateTime.utc_now()

    changeset =
      DeviceConnection.create_changeset(%{
        product_id: product_id,
        device_id: device.id,
        established_at: now,
        last_seen_at: now,
        status: :connecting
      })

    case Repo.insert(changeset) do
      {:ok, device_connection} ->
        Device
        |> where(id: ^device.id)
        |> Repo.update_all(set: [latest_connection_id: device_connection.id])

        Tracker.connecting(device)

        {:ok, device_connection}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Creates a device connection, reported from device socket
  """
  @spec device_connected(Device.t(), connection_id :: binary()) :: :ok | :error
  def device_connected(device, connection_id) do
    DeviceConnection
    |> where(id: ^connection_id)
    |> where([dc], not (dc.status == :disconnected))
    |> Repo.update_all(
      set: [
        last_seen_at: DateTime.utc_now(),
        status: :connected
      ]
    )
    |> case do
      {1, _} ->
        Tracker.online(device)
        :ok

      _ ->
        :error
    end
  end

  @doc """
  Updates the `last_seen_at`field for a device connection with current timestamp
  """
  @spec device_heartbeat(Device.t(), UUIDv7.t()) :: :ok | :error
  def device_heartbeat(device, id) do
    DeviceConnection
    |> where([dc], dc.id == ^id)
    |> where([dc], not (dc.status == :disconnected))
    |> Repo.update_all(
      set: [
        status: :connected,
        last_seen_at: DateTime.utc_now()
      ]
    )
    |> case do
      {1, _} ->
        Tracker.heartbeat(device)
        :ok

      _ ->
        :error
    end
  end

  @doc """
  Updates `status` and relevant timestamps for a device connection record,
  and stores the reason for disconnection if provided.
  """
  @spec device_disconnected(Device.t(), UUIDv7.t(), String.t() | nil) :: :ok | :error
  def device_disconnected(device, ref_id, reason \\ nil) do
    now = DateTime.utc_now()

    DeviceConnection
    |> where(id: ^ref_id)
    |> Repo.update_all(
      [
        set: [
          last_seen_at: now,
          disconnected_at: now,
          disconnected_reason: reason,
          status: :disconnected
        ]
      ],
      timeout: 60_000
    )
    |> case do
      {1, _} ->
        Tracker.offline(device)
        :ok

      _ ->
        :error
    end
  end

  @doc """
  Updates the connection `metadata` by merging in new metadata.
  """
  @spec merge_update_metadata(UUIDv7.t(), map()) :: :ok | :error
  def merge_update_metadata(ref_id, new_metadata) do
    DeviceConnection
    |> where(id: ^ref_id)
    |> update([dc], set: [metadata: fragment("? || ?::jsonb", dc.metadata, ^new_metadata)])
    |> Repo.update_all([])
    |> case do
      {1, _} -> :ok
      _ -> :error
    end
  end

  def clean_stale_connections() do
    interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
    jitter = Application.get_env(:nerves_hub, :device_last_seen_update_interval_jitter_seconds)

    max_jitter = ceil(jitter / 60)

    some_time_ago = DateTime.shift(DateTime.utc_now(), minute: -(interval + max_jitter + 1))

    {count, _} =
      DeviceConnection
      |> where(status: :connected)
      |> where([d], d.last_seen_at < ^some_time_ago)
      |> Repo.update_all(
        set: [
          status: :disconnected,
          disconnected_at: DateTime.utc_now(),
          disconnected_reason: "Stale connection"
        ]
      )

    if count > 0 do
      :telemetry.execute([:nerves_hub, :devices, :stale_connections], %{count: count})
    end

    :ok
  end

  def delete_old_connections() do
    interval = Application.get_env(:nerves_hub, :device_connection_max_age_days)
    delete_limit = Application.get_env(:nerves_hub, :device_connection_delete_limit)
    days_ago = DateTime.shift(DateTime.utc_now(), day: -interval)

    query =
      DeviceConnection
      |> join(:inner, [dc], d in Device, on: dc.device_id == d.id)
      |> where([dc, _d], dc.last_seen_at < ^days_ago)
      |> where([dc, _d], dc.status != :connected)
      |> where([dc, d], dc.id != d.latest_connection_id)
      |> select([dc], dc.id)
      |> limit(^delete_limit)
      |> order_by(:last_seen_at)

    {delete_count, _} =
      DeviceConnection
      |> where([d], d.id in subquery(query))
      |> Repo.delete_all(timeout: 60_000)

    if delete_count == 0 do
      :ok
    else
      # relax stress on Ecto pool and go again
      Process.sleep(2000)
      delete_old_connections()
    end
  end
end
