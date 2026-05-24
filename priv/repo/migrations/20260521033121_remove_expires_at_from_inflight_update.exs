defmodule NervesHub.Repo.Migrations.RemoveExpiresAtFromInflightUpdate do
  use Ecto.Migration

  def change() do
    alter table(:inflight_updates) do
      remove(:expires_at, :utc_datetime, null: false)
    end

    alter table(:deployments) do
      remove(:inflight_update_expiration_minutes, :integer)
    end
  end
end
