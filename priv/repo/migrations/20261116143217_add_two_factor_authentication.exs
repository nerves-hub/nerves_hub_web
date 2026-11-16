defmodule NervesHub.Repo.Migrations.AddTwoFactorAuthentication do
  use Ecto.Migration

  def change() do
    # A user's authenticator app, once they have set one up. Kept apart from
    # `users` so that loading a user never decrypts the secret: only signing in
    # and the account's two-factor page read this table.
    create table(:user_totps) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      # Encrypted with `NervesHub.Types.Encrypted`.
      add(:secret, :binary, null: false)
      # The start of the 30 second period of the last code accepted, so a code
      # can't be used twice.
      add(:last_used_at, :utc_datetime)
      # SHA-256 hashes of the recovery codes not used yet.
      add(:recovery_codes, {:array, :binary}, null: false, default: [])

      timestamps()
    end

    create(unique_index(:user_totps, [:user_id]))

    alter table(:orgs) do
      add(:require_two_factor, :boolean, null: false, default: false)
    end
  end
end
