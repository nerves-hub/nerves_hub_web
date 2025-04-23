defmodule NervesHub.Repo.Migrations.AddGoogleAuthFieldsToUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:profile_picture_url, :string, null: true)
      add(:google_id, :string, null: true)
      add(:google_hd, :string, null: true)
      add(:google_last_synced_at, :naive_datetime, null: true)
      modify(:password_hash, :string, null: true, from: {:string, null: false})
    end
  end
end
