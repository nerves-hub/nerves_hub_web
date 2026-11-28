defmodule NervesHub.AnalyticsRepo.Migrations.AddStateToDeviceComponentHistory do
  use Ecto.Migration

  def change() do
    # For "state_changed" rows: which state changed and what it became.
    # `detail` holds who or what changed it, where the device said. Empty on
    # every other event.
    alter table(:device_component_history) do
      add(:state, :"LowCardinality(String)")
      add(:value, :String)
    end
  end
end
