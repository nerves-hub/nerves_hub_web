defmodule NervesHub.Repo.Migrations.AddExtensions do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :extensions, :map, null: false, default: %{}
    end
    alter table(:devices) do
      add :extensions, :map, null: false, default: %{}
    end
  end
end
