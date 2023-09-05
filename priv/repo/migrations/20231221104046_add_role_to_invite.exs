defmodule NervesHub.Repo.Migrations.AddRoleToInvite do
  use Ecto.Migration

  def change do
    alter table(:invites) do
      add :role, :string
    end
  end
end
