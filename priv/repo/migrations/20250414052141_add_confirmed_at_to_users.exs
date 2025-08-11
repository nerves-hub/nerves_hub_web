defmodule NervesHub.Repo.Migrations.AddConfirmedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:confirmed_at, :naive_datetime)
    end

    flush()

    repo().query!("UPDATE users SET confirmed_at = NOW()")
  end
end
