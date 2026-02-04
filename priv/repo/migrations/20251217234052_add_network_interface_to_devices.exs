defmodule NervesHub.Repo.Migrations.AddNetworkInterfaceToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :network_interface, :string
    end
  end
end
