defmodule NervesHub.Repo.Migrations.CreateScriptRunnerDevices do
  use Ecto.Migration

  def change() do
    # One row per device a run targets, inserted up front at `pending` so the
    # full target set is a matter of record even if the coordinator never gets
    # to some of them. Terminal statuses also cover the devices nothing was sent
    # to: `offline` and `unsupported`.
    create table(:script_runner_devices) do
      add(:script_runner_id, references(:script_runners, on_delete: :delete_all), null: false)
      add(:device_id, references(:devices, on_delete: :delete_all), null: false)

      add(:status, :string, null: false, default: "pending")
      add(:output, :text)

      add(:started_at, :utc_datetime_usec)
      add(:finished_at, :utc_datetime_usec)

      # When `output` was cleared for outliving its retention period. Set
      # alongside clearing it, so the run's page can tell a device whose output
      # was removed from one that never sent any.
      add(:output_expired_at, :utc_datetime_usec)

      timestamps()
    end

    # A device appears at most once in a run. Also serves recording one device's
    # result, and the run's delete cascade.
    create(unique_index(:script_runner_devices, [:script_runner_id, :device_id]))

    # The dispatch loop claims a run's next pending devices in `id` order, every
    # few seconds while the run is active. With `id` last the claim reads only
    # the rows it takes, in order, rather than every pending row in the run and
    # then sorting them. The per-status counts use the leading two columns.
    create(index(:script_runner_devices, [:script_runner_id, :status, :id]))

    # For the FK's delete cascade when a device is hard deleted.
    create(index(:script_runner_devices, [:device_id]))

    # The retention job looks for output older than the cutoff. Partial, because
    # once output is cleared a row never matches again, and most rows in a long
    # lived instance will have been cleared.
    create(index(:script_runner_devices, [:finished_at], where: "output IS NOT NULL"))
  end
end
