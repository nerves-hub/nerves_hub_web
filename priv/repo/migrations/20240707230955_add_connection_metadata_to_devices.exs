defmodule NervesHub.Repo.Migrations.AddConnectionMetadataToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:connection_metadata, :map, null: false, default: %{})
    end
  end
end
