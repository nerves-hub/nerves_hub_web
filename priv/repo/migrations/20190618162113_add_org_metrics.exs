defmodule NervesHub.Repo.Migrations.AddOrgMetrics do
  use Ecto.Migration

  def change do
    create table(:org_metrics, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:org_id, references(:orgs, null: false))
      add(:devices, :integer, null: false)
      add(:bytes_transferred, :integer, null: false)
      add(:bytes_stored, :integer, null: false)
      add(:timestamp, :utc_datetime, null: false)
    end

    create(index(:org_metrics, [:org_id]))
  end
end
