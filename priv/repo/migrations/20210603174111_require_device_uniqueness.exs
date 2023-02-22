defmodule NervesHubWebCore.Repo.Migrations.RequireDeviceUniqueness do
  use Ecto.Migration

  def change do
    drop_if_exists(unique_index(:devices, [:org_id, :identifier], name: :devices_org_id_identifier_index, where: "deleted_at IS NULL"))

    # Deduplicate devices that may exist from previously being deleted
    execute "DELETE from devices where id not in (select max(id) from devices group by identifier)"

    create_if_not_exists(unique_index(:devices, [:org_id, :identifier], name: :devices_org_id_identifier_index))
  end
end
