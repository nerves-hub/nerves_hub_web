defmodule NervesHubWebCore.Repo.Migrations.AddTypeToOrg do
  use Ecto.Migration

  def change do
    NervesHubWebCore.Accounts.Org.Type.create_type()
    alter table(:orgs) do
      add(:type, NervesHubWebCore.Accounts.Org.Type.type())
    end
  end
end
