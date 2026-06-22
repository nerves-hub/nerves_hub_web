defmodule NervesHub.Repo.Migrations.UpdateLatestDeviceConnectionsTable do
  use Ecto.Migration

  def change() do
    alter table(:latest_device_connections) do
      add(:org_id, references("orgs", on_delete: :nilify_all))
      add(:product_id, references("products", on_delete: :nilify_all))

      add(:lib, :string)
      add(:lib_version, :string)

      add(:network_interface, :string)
    end
  end
end
