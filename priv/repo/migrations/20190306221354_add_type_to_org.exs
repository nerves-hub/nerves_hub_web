defmodule NervesHub.Repo.Migrations.AddTypeToOrg do
  use Ecto.Migration

  def change do
    NervesHub.Accounts.Org.Type.create_type()
    alter table(:orgs) do
      add(:type, NervesHub.Accounts.Org.Type.type())
    end
  end
end
