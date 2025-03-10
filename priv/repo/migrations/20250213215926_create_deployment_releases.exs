defmodule NervesHub.Repo.Migrations.CreateDeploymentReleases do
  use Ecto.Migration

  def change do
    create table(:deployment_releases) do
      add(:deployment_group_id, references(:deployments), null: false)
      add(:firmware_id, references(:firmwares), null: false)
      add(:archive_id, references(:archives))
      add(:created_by_id, references(:users), null: false)

      timestamps()
    end
  end
end
