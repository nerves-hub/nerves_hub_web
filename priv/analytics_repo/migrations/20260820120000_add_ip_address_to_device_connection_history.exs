defmodule NervesHub.AnalyticsRepo.Migrations.AddIpAddressToDeviceConnectionHistory do
  use Ecto.Migration

  def change() do
    alter table(:device_connection_history) do
      # Not `LowCardinality`, unlike its neighbours: a fleet's addresses are
      # closer to unique per device than to a handful of repeated values.
      add(:ip_address, :String)
    end
  end
end
