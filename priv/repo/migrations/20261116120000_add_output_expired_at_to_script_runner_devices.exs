defmodule NervesHub.Repo.Migrations.AddOutputExpiredAtToScriptRunnerDevices do
  use Ecto.Migration

  def change() do
    alter table(:script_runner_devices) do
      # When the device's output was cleared for having outlived its retention
      # period. Set alongside clearing `output`, so the run's page can tell a
      # device whose output was removed from one that never sent any.
      add(:output_expired_at, :utc_datetime_usec)
    end

    # The retention job looks for output older than the cutoff. Partial, because
    # once output is cleared a row never matches again, and most rows in a long
    # lived instance will have been cleared.
    create(index(:script_runner_devices, [:finished_at], where: "output IS NOT NULL"))
  end
end
