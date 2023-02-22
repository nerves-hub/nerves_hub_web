defmodule NervesHubWebCore.Repo.Migrations.AddOrgUsage do
  use Ecto.Migration

  def change do
    create table(:firmware_transfers, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:org_id, references(:orgs, null: false))
      add(:firmware_uuid, :string, null: false)
      add(:remote_ip, :string, null: false)
      add(:bytes_total, :integer, null: false)
      add(:bytes_sent, :integer, null: false)
      add(:timestamp, :utc_datetime, null: false)
    end
    create(
      unique_index(:firmware_transfers, [:org_id, :timestamp, :remote_ip, :firmware_uuid], name: :firmware_transfers_unique_index)
    )
  end
end
