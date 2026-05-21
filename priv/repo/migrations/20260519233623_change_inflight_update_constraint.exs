defmodule NervesHub.Repo.Migrations.ChangeInflightUpdateConstraint do
  use Ecto.Migration

  def change() do
    drop(unique_index(:inflight_updates, [:device_id, :deployment_id]))
    create(unique_index(:inflight_updates, [:device_id]))

    alter table(:inflight_updates) do
      modify(:deployment_id, references(:deployments, on_delete: :nilify_all),
        from: references(:deployments, on_delete: :nothing),
        null: true
      )

      modify(:device_id, references(:devices, on_delete: :delete_all), from: references(:devices, on_delete: :nothing))
    end
  end
end
