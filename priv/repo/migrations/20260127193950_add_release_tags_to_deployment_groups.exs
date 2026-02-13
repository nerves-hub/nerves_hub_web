defmodule NervesHub.Repo.Migrations.AddReleaseTagsToDeploymentGroups do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add :release_tags, {:array, :string}, default: [], null: false
    end
  end
end
