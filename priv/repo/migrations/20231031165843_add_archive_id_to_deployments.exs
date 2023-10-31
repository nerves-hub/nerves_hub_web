defmodule NervesHub.Repo.Migrations.AddArchiveIdToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:archive_id, references(:archives))
    end
  end
end
