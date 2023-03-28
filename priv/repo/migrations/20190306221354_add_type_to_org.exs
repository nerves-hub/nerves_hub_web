defmodule NervesHub.Repo.Migrations.AddTypeToOrg do
  use Ecto.Migration

  def change do
    execute "create type type as enum ('user', 'group');", "delete type type;"

    alter table(:orgs) do
      add(:type, :type)
    end
  end
end
