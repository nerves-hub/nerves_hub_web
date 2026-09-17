defmodule NervesHub.Repo.Migrations.AddRequiredToDeploymentReleases do
  use Ecto.Migration

  def change() do
    alter table(:deployment_releases) do
      add(:required, :boolean, null: false, default: false)
    end
  end
end
