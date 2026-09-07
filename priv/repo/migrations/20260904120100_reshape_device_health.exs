defmodule NervesHub.Repo.Migrations.ReshapeDeviceHealth do
  @moduledoc """
  `device_health` becomes one row per device: the current status, and nothing
  else.

  Three things go at once, because they only existed to support each other.
  The `data` payload held the whole health report, of which exactly two things
  were ever read — alarms (now `device_alarms`) and metadata (now merged onto
  the device connection) — while the rest duplicated what ClickHouse already
  holds. `devices.latest_health_id` existed to point at the newest of many
  rows; with one row per device the association finds it directly. And the
  history those rows made had no reader anywhere in the application, so the
  truncation worker was maintaining a table nothing queried.

  Nothing is carried across. Every device reports its status again on its next
  health report — and on reconnect, since `NervesHub.Extensions.Health` asks
  for one as it attaches — so the cost is that devices read as `unknown` until
  then, up to one idle reporting interval.
  """

  use Ecto.Migration

  def up() do
    # Before the table it references.
    alter table(:devices) do
      remove(:latest_health_id)
    end

    drop(table(:device_health))

    create table(:device_health) do
      add(:device_id, references(:devices, on_delete: :delete_all), null: false)

      add(:status, :string)
      add(:status_reasons, :map)

      timestamps(type: :utc_datetime_usec)
    end

    # One row per device: the upsert target, and what every read looks up by.
    create(unique_index(:device_health, [:device_id]))
  end

  def down() do
    # Deliberately not reversible: the report payloads and the report history
    # this dropped are not recoverable, so a `down` that recreated the old
    # shape would hand back an empty table pretending to be the old one.
    raise Ecto.MigrationError,
      message: "ReshapeDeviceHealth is not reversible; restore from a backup to recover device_health history"
  end
end
