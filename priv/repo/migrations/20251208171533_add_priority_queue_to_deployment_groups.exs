defmodule NervesHub.Repo.Migrations.AddPriorityQueueToDeploymentGroups do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add :priority_queue_enabled, :boolean, default: false, null: false
      add :priority_queue_concurrent_updates, :integer, default: 5, null: false
      add :priority_queue_firmware_version_threshold, :string
    end

    alter table(:inflight_updates) do
      add :priority_queue, :boolean, default: false, null: false
    end
  end
end
