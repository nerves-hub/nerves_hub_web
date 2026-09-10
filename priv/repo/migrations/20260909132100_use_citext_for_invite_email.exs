defmodule NervesHub.Repo.Migrations.UseCitextForInviteEmail do
  use Ecto.Migration

  def change() do
    execute("CREATE EXTENSION IF NOT EXISTS citext", "")

    alter table(:invites) do
      modify(:email, :citext, from: {:string, size: 255})
    end
  end
end
