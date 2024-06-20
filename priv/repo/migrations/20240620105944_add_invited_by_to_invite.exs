defmodule NervesHub.Repo.Migrations.AddInvitedByToInvite do
  use Ecto.Migration

  def change do
    alter table(:invites) do
      add(:invited_by_id, references(:users))
    end
  end
end
