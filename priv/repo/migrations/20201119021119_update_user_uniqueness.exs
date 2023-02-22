defmodule NervesHubWebCore.Repo.Migrations.UpdateUserUniqueness do
  use Ecto.Migration

  def change do
    drop_if_exists(unique_index(:users, [:email]))
    drop_if_exists(unique_index(:users, [:username]))
    drop_if_exists(unique_index(:orgs, [:name]))
    drop_if_exists(unique_index(:org_users, [:org_id, :user_id], name: "org_users_index"))
    drop_if_exists(unique_index(:products, [:org_id, :name], name: :products_org_id_name_index))
    drop_if_exists(unique_index(:devices, [:org_id, :identifier], name: :devices_org_id_identifier_index))

    create_if_not_exists(unique_index(:users, [:email], where: "deleted_at IS NULL"))
    create_if_not_exists(unique_index(:users, [:username], where: "deleted_at IS NULL"))
    create_if_not_exists(unique_index(:orgs, [:name], where: "deleted_at IS NULL"))
    create_if_not_exists(unique_index(:org_users, [:org_id, :user_id], name: "org_users_index", where: "deleted_at IS NULL"))
    create_if_not_exists(unique_index(:products, [:org_id, :name], name: :products_org_id_name_index, where: "deleted_at IS NULL"))
    create_if_not_exists(unique_index(:devices, [:org_id, :identifier], name: :devices_org_id_identifier_index, where: "deleted_at IS NULL"))
  end
end
