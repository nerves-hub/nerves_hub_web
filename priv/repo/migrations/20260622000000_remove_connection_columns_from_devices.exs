defmodule NervesHub.Repo.Migrations.RemoveConnectionColumnsFromDevices do
  use Ecto.Migration

  def change() do
    alter table(:devices) do
      remove(:connection_metadata, :map, null: false, default: %{})
      remove(:connection_types, {:array, :connection_type})
    end

    execute(
      "drop type connection_type",
      "create type connection_type as enum ('cellular', 'ethernet', 'wifi')"
    )
  end
end
