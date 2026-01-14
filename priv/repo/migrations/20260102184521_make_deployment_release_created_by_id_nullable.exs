defmodule NervesHub.Repo.Migrations.MakeDeploymentReleaseCreatedByIdNullable do
  use Ecto.Migration

  def up do
    alter table(:deployment_releases) do
      modify :created_by_id, :integer, null: true
    end
  end

  def down do
    # Note: This cannot be safely reversed as it would require
    # all existing rows to have a non-null created_by_id
    raise "This migration cannot be reversed"
  end
end
