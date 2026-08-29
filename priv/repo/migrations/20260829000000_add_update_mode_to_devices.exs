defmodule NervesHub.Repo.Migrations.AddUpdateModeToDevices do
  @moduledoc """
  Three-state update mode, replacing the `updates_enabled` boolean.

  `automatic` is today's behaviour — the deployment orchestrator pushes
  firmware on its own schedule. `off` freezes the device: its deployment group
  still names its target firmware, but only a manual push moves it.
  `device_managed` excludes the device from orchestrator pushes and lets the
  device ask for firmware on whatever schedule it likes.

  `updates_enabled` is backfilled into the new column and left in place for one
  release so a rollback still has its values. Nothing reads it after this
  migration; it is dropped in the next release.

  Only devices with updates disabled are touched by the backfill, so the
  statement skips the overwhelming majority of rows.
  """

  use Ecto.Migration

  def up() do
    alter table(:devices) do
      add(:update_mode, :string, null: false, default: "automatic")
    end

    execute("UPDATE devices SET update_mode = 'off' WHERE updates_enabled = false")
  end

  def down() do
    alter table(:devices) do
      remove(:update_mode)
    end
  end
end
