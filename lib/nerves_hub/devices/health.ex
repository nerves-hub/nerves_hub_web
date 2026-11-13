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

  @doc """
  The device's stored health status, or `nil` before its first verdict.
  """
  @spec current_status(pos_integer()) :: :unknown | :healthy | :warning | :unhealthy | nil
  def current_status(device_id) do
    DeviceHealth
    |> where(device_id: ^device_id)
    |> select([h], h.status)
    |> Repo.one()
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

  @doc """
  How many devices in each of the given products are `:healthy`, at
  `:warning` and `:unhealthy`, for a page that covers several products at
  once, such as the organizations home page.

  Devices that have reported no health are not counted, so a product whose
  devices have never reported reads as all zeroes rather than as healthy. A
  product with no device reporting at all is left out of the map.
  """
  @spec status_counts_by_product([pos_integer()]) :: %{
          pos_integer() => %{healthy: non_neg_integer(), warning: non_neg_integer(), unhealthy: non_neg_integer()}
        }
  def status_counts_by_product([]), do: %{}

  def status_counts_by_product(product_ids) when is_list(product_ids) do
    empty = %{healthy: 0, warning: 0, unhealthy: 0}

    Device
    |> join(:inner, [d], lh in assoc(d, :latest_health))
    |> where([d], d.product_id in ^product_ids)
    |> where([_, lh], lh.status in ^[:healthy, :warning, :unhealthy])
    |> Repo.exclude_deleted()
    |> group_by([d, lh], [d.product_id, lh.status])
    |> select([d, lh], {d.product_id, lh.status, count(d.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {product_id, status, count}, acc ->
      Map.update(acc, product_id, Map.put(empty, status, count), &Map.put(&1, status, count))
    end)
  end
end
