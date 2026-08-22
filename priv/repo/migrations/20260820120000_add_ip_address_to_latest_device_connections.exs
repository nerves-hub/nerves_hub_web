defmodule NervesHub.Repo.Migrations.AddIpAddressToLatestDeviceConnections do
  use Ecto.Migration

  def change() do
    alter table(:latest_device_connections) do
      add(:ip_address, :string)
    end
  end
end
