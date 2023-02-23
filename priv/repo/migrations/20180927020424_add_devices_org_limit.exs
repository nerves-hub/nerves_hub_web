defmodule NervesHub.Repo.Migrations.AddDevicesOrgLimit do
  use Ecto.Migration

  def change do
    alter table(:org_limits) do
      add(:devices, :integer)
    end
  end
end
