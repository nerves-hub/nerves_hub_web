defmodule NervesHubWebCore.Repo.Migrations.UsersNameToUsername do
  use Ecto.Migration

  def change do
    alter table(:invites) do
      remove(:name)
    end

    rename(table(:users), :name, to: :username)
    create(unique_index(:users, :username))
  end
end
