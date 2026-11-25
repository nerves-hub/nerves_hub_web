defmodule NervesHub.Repo.Migrations.AddPinnedDevicesIndexes do
  @moduledoc """
  A user's pinned devices, and the pins on a device.

  `(user_id, device_id)` serves what starts from the user: the pinned devices
  on their home page, whether they have pinned a device, unpinning one, the
  devices list's join to their pins, removing their pins on an org's devices
  when they leave it, and removing their pins when their account or user row
  is deleted. Each of those looks up the user's rows, most of them for one
  device among them.

  `(device_id)` serves what starts from the device: removing its pins when it
  is deleted or moved to another org, and the cascade when its row is
  destroyed.

  Without them, each of these reads every row in `pinned_devices`.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change() do
    create(index(:pinned_devices, [:user_id, :device_id], concurrently: true))
    create(index(:pinned_devices, [:device_id], concurrently: true))
  end
end
