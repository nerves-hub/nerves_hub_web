defmodule NervesHub.Repo.Migrations.AddProductIdToDeviceConnectionsTable do
  use Ecto.Migration

  def change do
    alter table(:device_connections) do
      add(:product_id, :integer)
    end

    create(index(:device_connections, [:product_id]))
  end
end
