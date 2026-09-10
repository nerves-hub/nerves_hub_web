defmodule NervesHub.Repo.Migrations.AddDeclinedAtToInvites do
  use Ecto.Migration

  def change() do
    alter table(:invites) do
      add(:declined_at, :utc_datetime)
    end
  end
end
