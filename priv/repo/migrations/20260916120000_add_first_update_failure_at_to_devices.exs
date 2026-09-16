defmodule NervesHub.Repo.Migrations.AddFirstUpdateFailureAtToDevices do
  use Ecto.Migration

  def change() do
    alter table(:devices) do
      # When the device's current run of failures began — the first failure
      # after its last successful update. `last_update_failure_at` says how
      # recent the trouble is; this says how long it has been going on, which
      # is what separates a device that failed twice this morning from one that
      # has not taken firmware in a fortnight.
      add(:first_update_failure_at, :utc_datetime)
    end
  end
end
