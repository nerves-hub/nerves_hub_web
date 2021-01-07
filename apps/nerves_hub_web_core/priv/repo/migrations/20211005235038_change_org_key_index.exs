defmodule NervesHubWebCore.Repo.Migrations.ChangeOrgKeyIndex do
  use Ecto.Migration

  def up do
    drop unique_index(:org_keys, [:key])
    create unique_index(:org_keys, [:org_id, :key], name: :org_keys_org_id_key_index)
  end

  def down do
    drop unique_index(:org_keys, [:org_id, :key], name: :org_keys_org_id_key_index)
    create unique_index(:org_keys, [:key])
  end
end
