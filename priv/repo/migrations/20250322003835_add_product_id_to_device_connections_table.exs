defmodule NervesHub.Repo.Migrations.AddProductIdToDeviceConnectionsTable do
  use Ecto.Migration

  def change do
    alter table(:device_connections) do
      add(:product_id, :bigint)
    end
  end
end
