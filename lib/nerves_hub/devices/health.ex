defmodule NervesHub.Devices.Health do
  @moduledoc """
  Context for recording and querying a device's current health status.

  One `DeviceHealth` row per device, replaced in place on each report. There is
  no report history to truncate and no `latest_health_id` to keep pointed at
  the newest row — see `NervesHub.Devices.DeviceHealth` for what moved where.
  """

  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Repo

  @doc """
  Record the device's current health status, replacing whatever it had.

  One statement: the row is the device's current verdict, so a second report
  overwrites the first rather than appending to it.
  """
  @spec save_device_health(health_report :: map()) ::
          {:ok, DeviceHealth.t()} | {:error, Ecto.Changeset.t()}
  def save_device_health(device_status) do
    device_status
    |> DeviceHealth.save()
    |> Repo.insert(
      on_conflict: {:replace, [:status, :status_reasons, :updated_at]},
      conflict_target: [:device_id],
      returning: true
    )
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
