defmodule NervesHub.Repo.Migrations.AddMfaFieldsToUsers do
  use Ecto.Migration

  def change() do
    alter table(:users) do
      add(:mfa_secret, :text)
      add(:mfa_enabled_at, :utc_datetime)
      add(:mfa_last_used_at, :utc_datetime)
      add(:mfa_recovery_codes, {:array, :text}, null: false, default: [])
    end
  end
end
