defmodule NervesHub.Repo.Migrations.AddConnectionInfoToDevices do
  use Ecto.Migration

  def change do
    execute "create type connection_type as enum ('cellular', 'ethernet', 'wifi');", "delete type connection_type;"

    alter table(:devices) do
      add(:connection_types, {:array, :connection_type})
    end
  end
end
