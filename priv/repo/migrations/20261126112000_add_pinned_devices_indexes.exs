defmodule NervesHub.Repo.Migrations.AddPinnedDevicesIndexes do
  @moduledoc """
  Index `pinned_devices` by user and by device.

  `(user_id, device_id)` serves lookups that start from a user: their home page
  pins, whether they pinned a device, unpinning, the devices list's join, and
  removing their pins when they leave an org or their account is deleted.
  `(device_id)` serves removing a device's pins when it is deleted or moves org,
  and the delete cascade. Neither is unique: nothing prevents a user pinning the
  same device twice, so existing rows may hold duplicates and a unique build
  would fail.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change() do
    create(index(:pinned_devices, [:user_id, :device_id], concurrently: true))
    create(index(:pinned_devices, [:device_id], concurrently: true))
  end
end
