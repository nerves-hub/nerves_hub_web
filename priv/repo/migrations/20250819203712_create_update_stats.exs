defmodule NervesHub.Repo.Migrations.CreateUpdateStats do
  use Ecto.Migration

  def change do
    create table(:update_stats, primary_key: false) do
      add(:product_id, references(:products))
      add(:device_id, references(:devices))
      add(:deployment_id, references(:deployments))
      add(:type, :string, null: false)
      add(:source_firmware_uuid, :uuid)
      add(:target_firmware_uuid, :uuid)
      add(:update_bytes, :integer, null: false)
      add(:saved_bytes, :integer, null: false)

      timestamps()
    end

    create(index("update_stats", [:product_id]))
    create(index("update_stats", [:device_id]))
    create(index("update_stats", [:deployment_id]))
  end
end
