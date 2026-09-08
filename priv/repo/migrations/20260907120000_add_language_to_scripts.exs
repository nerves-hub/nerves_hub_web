defmodule NervesHub.Repo.Migrations.AddLanguageToScripts do
  use Ecto.Migration

  # Adding a column with a constant default is a catalog-only change on
  # PostgreSQL 11 and up, so this neither rewrites the table nor holds a lock
  # while it runs. Every existing script predates any non-Elixir client, so the
  # default backfills them correctly.
  def change() do
    alter table(:scripts) do
      add(:language, :string, null: false, default: "elixir")
    end
  end
end
