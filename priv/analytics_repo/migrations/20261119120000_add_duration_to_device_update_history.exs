defmodule NervesHub.AnalyticsRepo.Migrations.AddDurationToDeviceUpdateHistory do
  use Ecto.Migration

  def change() do
    # How long the attempt took, in seconds, from when NervesHub sent the
    # update to when it ended: for a success, the device rejoining on its new
    # firmware. A deployment group's Stats tab reads it to say how long a
    # release takes to install, and whether deltas are quicker.
    #
    # 0 when unknown, as `deployment_id` is: an update the device took without
    # being sent one has no start, and nothing recorded before this column
    # existed has one either. Readers leave zeros out rather than counting them
    # as instant.
    alter table(:device_update_history) do
      add(:duration_seconds, :UInt32)
    end
  end
end
