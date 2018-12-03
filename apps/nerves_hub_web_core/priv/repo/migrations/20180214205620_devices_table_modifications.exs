defmodule NervesHubWebCore.Repo.Migrations.DevicesTableModifications do
  use Ecto.Migration

  def up do
    alter table(:devices) do
      add :description, :string
      add :product, :string
      add :platform, :string
      modify :current_version, :string, null: true
    end

    create unique_index(:devices, [:tenant_id, :identifier])
  end

  def down do
    drop unique_index(:devices, [:tenant_id, :identifier])

    alter table(:devices) do
      remove :description
      remove :product
      remove :platform
      modify :current_version, :string, null: false
    end
  end
end
