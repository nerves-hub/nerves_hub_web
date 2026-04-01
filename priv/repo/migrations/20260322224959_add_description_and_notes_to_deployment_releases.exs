defmodule NervesHub.Repo.Migrations.AddDescriptionAndNotesToDeploymentReleases do
  use Ecto.Migration

  def change() do
    alter table(:deployment_releases) do
      add(:description, :string, null: true, size: 100)
      add(:notes, :string, null: true, size: 1_000)
    end
  end
end
