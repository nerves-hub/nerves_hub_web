defmodule NervesHub.Devices.Health do
  @moduledoc """
  Context for recording and querying device health.

  Health reports are stored as `DeviceHealth` rows; the most recent report is
  denormalized onto the device as `latest_health`. Old reports are periodically
  truncated.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Repo

  @spec save_device_health(health_report :: map()) ::
          {:ok, DeviceHealth.t()} | {:error, Ecto.Changeset.t()}
  def save_device_health(device_status) do
    Multi.new()
    |> Multi.insert(:insert_health, DeviceHealth.save(device_status))
    |> Ecto.Multi.update_all(:update_device, &update_health_on_device/1, [])
    |> Repo.transact()
    |> case do
      {:ok, %{insert_health: health}} ->
        {:ok, health}

      {:error, _, changeset, _} ->
        {:error, changeset}
    end
  end

  defp update_health_on_device(%{insert_health: health}) do
    Device
    |> where(id: ^health.device_id)
    |> update(set: [latest_health_id: ^health.id])
  end

  def truncate_device_health() do
    interval =
      Application.get_env(:nerves_hub, :device_health_days_to_retain)

    delete_limit = Application.get_env(:nerves_hub, :device_health_delete_limit)
    time_ago = DateTime.shift(DateTime.utc_now(), day: -interval)

    query =
      DeviceHealth
      |> join(:inner, [dh], d in Device, on: dh.device_id == d.id)
      |> where([dh, _d], dh.inserted_at < ^time_ago)
      |> where([dh, d], dh.id != d.latest_health_id)
      |> select([dh], dh.id)
      |> limit(^delete_limit)

    {delete_count, _} =
      DeviceHealth
      |> where([dh], dh.id in subquery(query))
      |> Repo.delete_all(timeout: 30_000)

    if delete_count == 0 do
      :ok
    else
      # relax stress on Ecto pool and go again
      Process.sleep(2000)
      truncate_device_health()
    end
  end

  @doc """
  The report payload (`data`) of the device's latest health row, or an empty
  map. Used when a status transition happens with no report to ride on —
  the row recording it carries the last reported alarms and metadata
  forward rather than blanking what the UI shows.
  """
  @spec latest_report_data(pos_integer()) :: map()
  def latest_report_data(device_id) do
    Device
    |> join(:inner, [d], lh in assoc(d, :latest_health))
    |> where([d], d.id == ^device_id)
    |> select([_, lh], lh.data)
    |> Repo.one() || %{}
  end

  def health_status_count(product, status) do
    Device
    |> join(:inner, [d], lh in assoc(d, :latest_health))
    |> where(product_id: ^product.id)
    |> where([_, lh], lh.status == ^status)
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end
end
