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

      timestamps()
    end

    # A device appears at most once in a run, which is also what makes the
    # up-front `insert_all` safe to retry.
    create(unique_index(:script_runner_devices, [:script_runner_id, :device_id]))

    # The dispatch loop claims the next batch of pending devices for one run,
    # and the progress counts group by status within a run.
    create(index(:script_runner_devices, [:script_runner_id, :status]))

    # "What has been run on this device" — and the FK's own delete cascade.
    create(index(:script_runner_devices, [:device_id]))
  end
end
