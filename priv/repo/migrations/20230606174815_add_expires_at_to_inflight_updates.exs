defmodule NervesHub.Repo.Migrations.AddExpiresAtToInflightUpdates do
  use Ecto.Migration

  def up do
    alter table(:inflight_updates) do
      add(:expires_at, :utc_datetime)
    end

    alter table(:deployments) do
      add(:inflight_update_expiration_minutes, :integer, default: 60, null: false)
    end

    execute """
      update inflight_updates
      set expires_at = now() + interval '1 minute' * deployments.inflight_update_expiration_minutes
      from deployments
      where deployments.id = inflight_updates.deployment_id;
    """

    alter table(:inflight_updates) do
      modify(:expires_at, :utc_datetime, null: false)
    end
  end

  def down do
    alter table(:deployments) do
      remove(:inflight_update_expiration_minutes)
    end

    alter table(:inflight_updates) do
      remove(:expires_at)
    end
  end
end
