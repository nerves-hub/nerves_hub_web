defmodule NervesHub.Repo.Migrations.AddDeploymentWorkflowSteps do
  use Ecto.Migration

  def change() do
    create table(:deployment_workflow_steps) do
      add(:deployment_release_id, references(:deployment_releases), null: false)
      add(:skipped_by_id, references(:users), null: true)
      add(:approved_by_id, references(:users), null: true)
      add(:number, :integer, null: false)
      add(:name, :string, null: true, size: 50)
      add(:description, :string, null: true, size: 100)
      add(:status, :string, null: false)
      add(:type, :string, null: false)
      add(:matching_conditions, :map, null: false, default: %{})
      add(:concurrency, :integer, default: 10)
      add(:approved_at, :naive_datetime_usec, null: true)
      add(:started_at, :naive_datetime_usec, null: true)
      add(:skipped_at, :naive_datetime_usec, null: true)
      add(:finished_at, :naive_datetime_usec, null: true)
    end
  end
end
