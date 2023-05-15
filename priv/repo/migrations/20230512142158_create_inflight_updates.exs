defmodule NervesHub.Repo.Migrations.CreateInflightUpdates do
  use Ecto.Migration

  def change do
    create table(:inflight_updates) do
      add(:device_id, references(:devices), null: false)
      add(:deployment_id, references(:deployments), null: false)
      add(:firmware_id, references(:firmwares), null: false)

      add(:firmware_uuid, :uuid, null: false)
      add(:status, :string, default: "pending", null: false)

      timestamps(updated_at: false)
    end

    create index(:inflight_updates, [:device_id, :deployment_id], unique: true)
  end
end
