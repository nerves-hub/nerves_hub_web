defmodule NervesHub.Repo.Migrations.AddDeltaStatusToDeploymentReleases do
  use Ecto.Migration

  def up() do
    alter table(:deployment_releases) do
      add(:delta_status, :string, null: false, default: "ready")
    end

    # Carry over what each deployment group's status was saying about its current
    # release, so a group waiting on deltas goes on waiting across the deploy.
    execute("""
    UPDATE deployment_releases AS r
    SET delta_status =
      CASE d.status
        WHEN 'preparing' THEN 'preparing'
        WHEN 'deltas_failed' THEN 'failed'
        WHEN 'unknown_error' THEN 'failed'
        ELSE 'ready'
      END
    FROM deployments AS d
    WHERE d.current_deployment_release_id = r.id
    """)
  end

  def down() do
    alter table(:deployment_releases) do
      remove(:delta_status)
    end
  end
end
