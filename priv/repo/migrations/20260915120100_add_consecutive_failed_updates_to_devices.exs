defmodule NervesHub.Repo.Migrations.AddConsecutiveFailedUpdatesToDevices do
  use Ecto.Migration

  def change() do
    alter table(:devices) do
      # How many update attempts in a row have ended badly since this device
      # last took firmware successfully. `update_attempts` cannot answer this:
      # it is emptied every time the device is put in the penalty box, which is
      # exactly the moment the count starts to matter.
      add(:consecutive_failed_updates, :integer, null: false, default: 0)

      # When the most recent of those attempts ended, so a device failing right
      # now can be told from one that failed and has since gone quiet.
      add(:last_update_failure_at, :utc_datetime)
    end
  end
end
