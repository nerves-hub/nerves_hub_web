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

  The update carries a `WHERE`, so a report that agrees with the stored
  verdict writes nothing — which is most of them, since a device's status
  changes far more rarely than it reports. That case answers `{:ok,
  :unchanged}`.
  """
  @spec save_device_health(health_report :: map()) ::
          {:ok, DeviceHealth.t()} | {:ok, :unchanged} | {:error, Ecto.Changeset.t()}
  def save_device_health(device_status) do
    device_status
    |> DeviceHealth.save()
    |> Repo.insert(
      on_conflict: replace_when_changed(),
      conflict_target: [:device_id],
      returning: true
    )
  rescue
    # `ON CONFLICT DO UPDATE ... WHERE` returns no row when the verdict is
    # unchanged, and Ecto reads "no row came back" as a stale entry. Here it
    # is the answer rather than an error.
    Ecto.StaleEntryError -> {:ok, :unchanged}
  end

  # `IS DISTINCT FROM` rather than `!=` because either side can be NULL:
  # `status_reasons` is null whenever no level is engaged, which is the
  # common case, and `NULL != NULL` is null, not true.
  defp replace_when_changed() do
    from(h in DeviceHealth,
      where:
        fragment("? IS DISTINCT FROM ?", h.status, fragment("EXCLUDED.status")) or
          fragment("? IS DISTINCT FROM ?", h.status_reasons, fragment("EXCLUDED.status_reasons")),
      update: [
        set: [
          status: fragment("EXCLUDED.status"),
          status_reasons: fragment("EXCLUDED.status_reasons"),
          updated_at: fragment("EXCLUDED.updated_at")
        ]
      ]
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
