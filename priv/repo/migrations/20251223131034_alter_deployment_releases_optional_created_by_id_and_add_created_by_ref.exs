defmodule NervesHub.Repo.Migrations.AlterDeploymentReleasesOptionalCreatedByIdAndAddCreatedByRef do
  use Ecto.Migration

  def change do
    alter table(:deployment_releases) do
      modify(:created_by_id, references(:users), null: true, from: {references(:users), null: false})
      add(:created_by_ref, :string, null: false, default: "")
    end
  end
end
