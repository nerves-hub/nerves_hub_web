defmodule NervesHub.Repo.Migrations.UniqueOrgNames do
  use Ecto.Migration

  def change do
    create(unique_index(:orgs, [:name]))
  end
end
