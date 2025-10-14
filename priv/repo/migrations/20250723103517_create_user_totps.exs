defmodule NervesHub.Repo.Migrations.CreateUserTotps do
  use Ecto.Migration

  def change do
    create table(:user_totps) do
      add :secret, :binary, null: false
      add :backup_codes, :map
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:user_totps, [:user_id])
  end
end
