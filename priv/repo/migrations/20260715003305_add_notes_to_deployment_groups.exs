defmodule NervesHub.Repo.Migrations.AddNotesToDeploymentGroups do
  use Ecto.Migration

  def change() do
    alter table(:deployments) do
      add(:notes, :text, null: true)
    end
  end
end
