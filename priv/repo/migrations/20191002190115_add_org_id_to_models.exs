defmodule NervesHub.Repo.Migrations.AddOrgIdToModels do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add :org_id, references(:orgs, on_delete: :nothing, null: true)
    end

    alter table(:deployments) do
      add :org_id, references(:orgs, on_delete: :nothing, null: true)
    end

    alter table(:firmwares) do
      add :org_id, references(:orgs, on_delete: :nothing, null: true)
    end

    alter table(:device_certificates) do
      add :org_id, references(:orgs, on_delete: :nothing, null: true)
    end
  end
end
