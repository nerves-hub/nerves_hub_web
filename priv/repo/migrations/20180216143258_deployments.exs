defmodule NervesHub.Repo.Migrations.Deployments do
  use Ecto.Migration

  def change do
    create table(:deployments) do
      add(:tenant_id, references(:tenants), null: false)
      add(:firmware_id, references(:firmwares), null: false)
      add(:name, :string, null: false)
      add(:conditions, :map, default: "{}", null: false)
      add(:status, :string, null: false)

      timestamps()
    end
  end
end
