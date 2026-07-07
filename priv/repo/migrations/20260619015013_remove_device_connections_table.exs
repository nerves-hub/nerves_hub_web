defmodule NervesHub.Repo.Migrations.RemoveDeviceConnectionsTable do
  use Ecto.Migration

  def up() do
    drop(table("device_connections"))
  end

  def down() do
    # Note: This cannot be safely reversed as it would require
    # all existing rows to have a non-null firmware_id and archive_id
    raise "This migration cannot be reversed"
  end
end
