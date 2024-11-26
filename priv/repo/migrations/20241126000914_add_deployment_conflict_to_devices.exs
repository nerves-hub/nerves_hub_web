defmodule NervesHub.Repo.Migrations.AddDeploymentConflictToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:deployment_conflict, :text)
    end
  end
end
