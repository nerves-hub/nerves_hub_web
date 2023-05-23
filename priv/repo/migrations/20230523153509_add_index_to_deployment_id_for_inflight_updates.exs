defmodule NervesHub.Repo.Migrations.AddIndexToDeploymentIdForInflightUpdates do
  use Ecto.Migration

  def change do
    create index(:inflight_updates, :deployment_id)
  end
end
