defmodule NervesHub.Repo.Migrations.CreateDeviceAlarms do
  use Ecto.Migration

  def change() do
    # Currently-raised alarms only: resolving deletes the row, and the
    # raise/resolve transitions live in ClickHouse as `device_alarm_history`.
    # That keeps this table one row per (device, raised alarm) — small enough
    # to stay hot, and every read it serves is a "what is alarming now"
    # question.
    create table(:device_alarms) do
      add(:device_id, references(:devices, on_delete: :delete_all), null: false)

      # Denormalised: every read is product-scoped (the alarm filters, the
      # product alarm counts), and the write path has it to hand on
      # `DeviceInfo`. Saves the join back to devices on the hot queries.
      add(:product_id, references(:products, on_delete: :delete_all), null: false)

      # Stored without the `Elixir.` prefix the Erlang alarm handler carries —
      # normalised on write, so readers and filters match what is displayed
      # rather than trimming at every call site.
      add(:alarm, :string, null: false)
      add(:description, :text)

      # When this alarm was first seen raised, not when it was last reported.
      # Reports carry the whole current alarm set every time, so the upsert
      # deliberately leaves this column alone; see `NervesHub.Devices.Alarms`.
      add(:raised_at, :utc_datetime_usec, null: false)
    end

    # The upsert target, and what "does this device have any alarm" reads.
    create(unique_index(:device_alarms, [:device_id, :alarm]))

    # `get_current_alarm_types/1` (distinct alarms in a product) and
    # `current_alarms_count/1` (devices alarming in a product).
    create(index(:device_alarms, [:product_id, :alarm]))
    create(index(:device_alarms, [:product_id, :device_id]))
  end
end
