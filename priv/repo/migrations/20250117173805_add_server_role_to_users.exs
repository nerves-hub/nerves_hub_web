defmodule NervesHub.Repo.Migrations.AddServerRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :server_role, :string
    end
  end
end
