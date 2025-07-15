defmodule NervesHub.Repo.Migrations.AddToolFieldsForFirmwareAndDeltas do
  use Ecto.Migration

  def change do
    alter table(:firmwares) do
      add :tool, :string, default: "fwup"
      # Default is a very safe value
      add :tool_delta_required_version, :string, default: "1.13.0"
      # Minimize risk of preventing an update
      add :tool_full_required_version, :string, default: "0.2.0"
      add :tool_metadata, :map, default: %{}
    end

    alter table(:firmware_deltas) do
      add :tool, :string, default: "fwup"
      add :tool_metadata, :map, default: %{}
      add :size, :integer, default: 0
      add :source_size, :integer, default: 0
      add :target_size, :integer, default: 0
    end
  end
end
