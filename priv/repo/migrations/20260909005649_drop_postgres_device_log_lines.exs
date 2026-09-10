defmodule NervesHub.Repo.Migrations.DropPostgresDeviceLogLines do
  @moduledoc """
  Drop the Postgres `device_log_lines` table, which nothing has written to for
  over a year.

  It was created in `create_device_log_lines` on 2025-05-03; three days later
  `NervesHub.AnalyticsRepo.Migrations.DeviceLogLines` created the ClickHouse
  table that log lines have gone to ever since. `NervesHub.Devices.LogLine`
  declares `Ch` column types and resolves against the analytics repo, so the
  Postgres table has been unreachable from the application the whole time.

  Its one remaining effect was a foreign key onto `devices`, which made
  permanently destroying a device fail for any device that had logged a line
  before the switch.
  """

  use Ecto.Migration

  def up() do
    drop(table(:device_log_lines))
  end

  def down() do
    create table(:device_log_lines, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:device_id, references(:devices), null: false)
      add(:product_id, references(:products), null: false)
      add(:level, :string, null: false)
      add(:message, :text, null: false)
      add(:meta, :map, null: false, default: %{})
      add(:logged_at, :naive_datetime_usec, null: false)
    end

    create(index("device_log_lines", [:device_id]))
    create(index("device_log_lines", [:product_id]))
    create(index("device_log_lines", [:logged_at]))
  end
end
