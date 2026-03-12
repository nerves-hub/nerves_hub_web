defmodule NervesHub.Repo.Migrations.RemoveFirmwareIdAndArchiveIdFromDeployments do
  use Ecto.Migration

  def up() do
    alter table(:deployments) do
      remove(:firmware_id)
      remove(:archive_id)
    end
  end

  def down() do
    # Note: This cannot be safely reversed as it would require
    # all existing rows to have a non-null firmware_id and archive_id
    raise "This migration cannot be reversed"
  end
end
