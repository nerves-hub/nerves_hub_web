defmodule NervesHub.Repo.Migrations.AddStatusColumnsToDeploymentGroups do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:status, :string, default: "ok", null: false)
      add(:paused_source, :string)
      add(:paused_reason, :string)
    end
  end
end
