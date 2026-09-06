defmodule NervesHub.Devices.Health do
  @moduledoc """
  Context for recording and querying a device's current health status.

  One `DeviceHealth` row per device, replaced in place on each report. There is
  no report history to truncate and no `latest_health_id` to keep pointed at
  the newest row — see `NervesHub.Devices.DeviceHealth` for what moved where.
  """

  import Ecto.Query

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Devices.DeviceHealthHistory
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  # More than five moves into a warning or unhealthy verdict in an hour. Only
  # levels that engaged count: settling back to healthy is the recovery, not
  # the symptom.
  @flapping_threshold 5
  @flapping_statuses ["warning", "unhealthy"]

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

  @doc """
  The product's devices whose health has been flapping: those with more than
  `@flapping_threshold` moves into a warning or unhealthy verdict in the last
  hour, worst first, capped at ten.

  Only transitions are recorded, so a count here is that many genuine changes
  of mind about the device rather than that many reports. A device sitting
  steadily unhealthy contributes one; a device crossing its threshold back and
  forth contributes one each time, which is the behaviour worth surfacing.

  Reads ClickHouse (`NervesHub.Devices.DeviceHealthHistory`); callers are
  expected to check that analytics is enabled first.
  """
  @spec flapping_health(Product.t()) :: [{Device.t(), non_neg_integer()}]
  def flapping_health(%Product{} = product) do
    DeviceHealthHistory
    |> where([h], h.org_id == ^product.org_id and h.product_id == ^product.id)
    |> where([h], h.timestamp >= fragment("now() - INTERVAL 1 HOUR"))
    |> where([h], h.status in ^@flapping_statuses)
    |> group_by([h], h.device_id)
    |> having([h], fragment("count() > ?", ^@flapping_threshold))
    |> select([h], %{device_id: h.device_id, count: fragment("count()")})
    |> order_by([h], desc: fragment("count()"))
    |> limit(10)
    |> AnalyticsRepo.all()
    |> Devices.with_counts(product)
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
