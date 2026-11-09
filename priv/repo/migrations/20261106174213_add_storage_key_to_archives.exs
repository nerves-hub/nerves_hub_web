defmodule NervesHub.Repo.Migrations.AddStorageKeyToArchives do
  use Ecto.Migration

  # Where an archive's file is stored. Archives uploaded before this have none,
  # and their files stay where they always were, at a path made from the UUID
  # alone, so nothing here moves or rewrites a file.
  def change() do
    alter table(:archives) do
      add(:storage_key, :string)
    end

    # Looked up before a file is deleted, to check no other archive still uses it.
    create(unique_index(:archives, [:storage_key]))
  end
end
