defmodule NervesHub.Repo.Migrations.RemoveFirmwareIdAndArchiveIdFromDeployments do
  use Ecto.Migration

  def change() do
    alter table(:deployments) do
      remove(:firmware_id)
      remove(:archive_id)
    end
  end
end
