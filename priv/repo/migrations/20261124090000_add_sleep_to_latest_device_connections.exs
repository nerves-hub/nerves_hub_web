defmodule NervesHub.Repo.Migrations.AddSleepToLatestDeviceConnections do
  use Ecto.Migration

  def change() do
    # When a device that said it was going to sleep expects to be back, and
    # (reserved, not yet set) when it was found not to be. Both belong to the
    # connection that ended with the sleep, so a device that wakes and
    # connects again replaces them along with the rest of the row.
    #
    # How it went to sleep is `disconnected_reason`. Existing rows keep the
    # "Stale connection" they were written with: `DisconnectReason` still
    # loads it, and rewriting a row per device for a label is not worth it.
    alter table(:latest_device_connections) do
      add(:expected_wake_at, :utc_datetime_usec)
      add(:wake_missed_at, :utc_datetime_usec)
    end
  end
end
