defmodule NervesHub.Repo.Migrations.AddTagsToScripts do
  use Ecto.Migration

  def change do
    alter table(:scripts) do
      add :tags, {:array, :string}
    end
  end
end
