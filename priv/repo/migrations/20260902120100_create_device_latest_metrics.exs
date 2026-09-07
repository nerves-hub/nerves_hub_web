defmodule NervesHub.Repo.Migrations.CreateDeviceLatestMetrics do
  use Ecto.Migration

  def change() do
    # One row per device, holding the most recent report as it arrived. The
    # history lives in ClickHouse, which cannot be joined against `devices` --
    # and the devices list has to filter on a metric value alongside the rest of
    # a device's state, in one query. So the latest set is denormalised here,
    # the same move `devices.latest_health_id` and `device_connections` make.
    #
    # Its own table rather than a column on `devices`: while anyone has a device
    # page open it reports once a minute, and that would otherwise churn the
    # hottest row in the system.
    #
    # No backfill. Every device that reports fills its own row in.
    create table(:device_latest_metrics, primary_key: false) do
      add(:device_id, references(:devices, on_delete: :delete_all), primary_key: true, null: false)
      add(:product_id, references(:products, on_delete: :delete_all), null: false)

      # `{metric name => value}` exactly as the device reported it, after
      # `NervesHub.Devices.Metrics` has trimmed what it will not store.
      add(:metrics, :map, null: false, default: "{}")

      # When the device took the readings, not when the row was written. What
      # the device page shows as "last updated", and what keeps an out-of-order
      # batch from moving the latest set backwards.
      add(:reported_at, :utc_datetime_usec, null: false)
    end

    # Scopes the advanced-query autosuggest list, which asks for every metric
    # name a product's devices have reported.
    create(index(:device_latest_metrics, [:product_id]))

    # Deliberately no index on `metrics`. The devices list compares
    # `(metrics->>'<key>')::float` against a number, and no GIN opclass serves
    # that -- GIN on jsonb answers containment and key-existence, not a range
    # over a value extracted as text and cast. An expression index would, but
    # only per key, and the keys are device-defined. Both callers reach this
    # table through `device_id`, which is the primary key, so what is scanned is
    # one row per device in the product rather than one row per reading.
  end
end
