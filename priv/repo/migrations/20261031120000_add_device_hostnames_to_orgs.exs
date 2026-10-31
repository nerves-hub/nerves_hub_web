defmodule NervesHub.Repo.Migrations.AddDeviceHostnamesToOrgs do
  use Ecto.Migration

  def change() do
    alter table(:orgs) do
      add(:device_hostnames, {:array, :string}, null: false, default: [])
    end

    # Looked up by hostname on every device connection.
    create(index(:orgs, [:device_hostnames], using: :gin))
  end
end
