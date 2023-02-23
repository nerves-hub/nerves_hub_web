defmodule NervesHub.Repo.Migrations.AddDeviceFirmwareMetadataRemoveLastLink do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :firmware_metadata, :map
    end
  end
end
