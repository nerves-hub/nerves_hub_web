defmodule NervesHub.Repo.Migrations.AddFeatures do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :features, :map, null: false, default: %{enabled: [], disabled: []}
    end
    alter table(:devices) do
      add :features, :map, null: false, default: %{enabled: [], disabled: []}
    end
  end
end
