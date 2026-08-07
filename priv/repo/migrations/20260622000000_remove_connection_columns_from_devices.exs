defmodule NervesHub.Repo.Migrations.RemoveConnectionColumnsFromDevices do
  use Ecto.Migration

  def change() do
    alter table(:devices) do
      # Removing connection_status also drops the index created in
      # AddConnectionStatusIndexToDevices.
      remove(:connection_status, :string)
      remove(:connection_established_at, :utc_datetime)
      remove(:connection_disconnected_at, :utc_datetime)
      remove(:connection_last_seen_at, :utc_datetime)
      remove(:connection_metadata, :map, null: false, default: %{})
      remove(:connection_types, {:array, :connection_type})
    end

    execute(
      "drop type connection_type",
      "create type connection_type as enum ('cellular', 'ethernet', 'wifi')"
    )
  end
end
