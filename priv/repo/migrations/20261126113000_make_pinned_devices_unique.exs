defmodule NervesHub.Repo.Migrations.MakePinnedDevicesUnique do
  @moduledoc """
  A user pins a device at most once, so `(user_id, device_id)` is unique.

  A user and device with two rows can't be unpinned, and the device shows
  twice in that user's devices list. The extra rows are deleted first,
  keeping the lowest `id` of each pair, and the unique index then replaces
  the plain one on the same columns, serving the same queries.

  Rows with a NULL `user_id` or `device_id` stay. They match no user's
  pins, and the index treats NULLs as distinct, so they don't stop it.

  The index is built concurrently. A concurrent unique build fails when a
  duplicate is there as it starts or is inserted while it runs, and leaves
  an invalid index of its name behind. So any index of that name is
  dropped first, and running the migration again deletes what was inserted
  meanwhile and builds the index anew.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @unique_name :pinned_devices_user_id_device_id_unique_index

  def up() do
    drop_if_exists(index(:pinned_devices, [:user_id, :device_id], name: @unique_name, concurrently: true))

    execute("""
    DELETE FROM pinned_devices AS duplicate
    USING pinned_devices AS kept
    WHERE duplicate.user_id = kept.user_id
      AND duplicate.device_id = kept.device_id
      AND duplicate.id > kept.id
    """)

    create(unique_index(:pinned_devices, [:user_id, :device_id], name: @unique_name, concurrently: true))
    drop_if_exists(index(:pinned_devices, [:user_id, :device_id], concurrently: true))
  end

  def down() do
    drop_if_exists(index(:pinned_devices, [:user_id, :device_id], concurrently: true))
    create(index(:pinned_devices, [:user_id, :device_id], concurrently: true))
    drop(index(:pinned_devices, [:user_id, :device_id], name: @unique_name, concurrently: true))
  end
end
