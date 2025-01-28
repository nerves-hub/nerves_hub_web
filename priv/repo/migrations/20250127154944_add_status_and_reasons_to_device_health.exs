defmodule NervesHub.Repo.Migrations.AddStatusAndReasonsToDeviceHealth do
  use Ecto.Migration

  def change do
    alter table(:device_health) do
      add :status, :string
      add :status_reasons, :map
    end
  end
end
