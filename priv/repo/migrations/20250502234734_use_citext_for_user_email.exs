defmodule NervesHub.Repo.Migrations.UseCitextForUserEmail do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS citext")

    alter table(:users) do
      modify(:email, :citext, from: {:string})
    end
  end
end
