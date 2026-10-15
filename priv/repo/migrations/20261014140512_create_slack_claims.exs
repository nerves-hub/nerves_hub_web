defmodule NervesHub.Repo.Migrations.CreateSlackClaims do
  use Ecto.Migration

  def change() do
    # Something done from Slack that should not be done again for a while:
    # a request Slack sent (by trigger id), or a device asked to reboot.
    # Held in the database so that every web node sees it.
    create table(:slack_claims, primary_key: false) do
      add(:key, :string, primary_key: true)
      add(:holder, :string)
      add(:expires_at, :utc_datetime_usec, null: false)
    end

    create(index(:slack_claims, [:expires_at]))
  end
end
