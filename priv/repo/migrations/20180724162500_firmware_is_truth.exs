defmodule NervesHubWebCore.Repo.Migrations.FirmwareIsTruth do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      remove(:target_deployment_id)
      remove(:product_id)
      remove(:architecture)
      remove(:platform)
    end

    rename(table(:devices), :current_firmware_id, to: :last_known_firmware_id)

    alter table(:deployments) do
      remove(:product_id)
    end

    alter table(:firmwares) do
      remove(:tenant_id)
    end
  end
end
