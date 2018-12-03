defmodule NervesHubWebCore.Repo.Migrations.Devices do
  use Ecto.Migration

  def up do
    create table(:devices) do
      add :tenant_id, references(:tenants), null: false
      add :identifier, :string, null: false
      add :current_version, :string, null: false
      add :target_version, :string
      add :last_communication, :utc_datetime
      add :architecture, :string
      add :tags, {:array, :string}

      timestamps()
    end
  end

  def down do
    drop table(:devices)
  end
end
