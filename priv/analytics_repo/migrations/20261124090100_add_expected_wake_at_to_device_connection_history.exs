defmodule NervesHub.AnalyticsRepo.Migrations.AddExpectedWakeAtToDeviceConnectionHistory do
  use Ecto.Migration

  def change() do
    # When a device that went to sleep said it would be back, so a later
    # connection can be compared with it: whether devices wake when they say
    # they will, and how long a product's devices spend asleep. How it went to
    # sleep is `disconnected_reason`, already a column.
    alter table(:device_connection_history) do
      add(:expected_wake_at, :"Nullable(DateTime64(6, 'UTC'))")
    end
  end
end
