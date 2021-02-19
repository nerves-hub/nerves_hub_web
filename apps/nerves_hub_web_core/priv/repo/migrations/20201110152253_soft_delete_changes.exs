defmodule NervesHubWebCore.Repo.Migrations.SoftDeleteChanges do
  use Ecto.Migration

  def change do
    alter(table(:orgs)) do
      add(:deleted_at, :utc_datetime)
    end

    alter(table(:org_users)) do
      add(:deleted_at, :utc_datetime)
    end

    alter(table(:devices)) do
      add(:deleted_at, :utc_datetime)
    end

    alter(table(:users)) do
      add(:deleted_at, :utc_datetime)
    end

    alter(table(:products)) do
      add(:deleted_at, :utc_datetime)
    end

    create_if_not_exists(index(:orgs, [:deleted_at]))
    create_if_not_exists(index(:org_users, [:deleted_at]))
    create_if_not_exists(index(:devices, [:deleted_at]))
    create_if_not_exists(index(:users, [:deleted_at]))
    create_if_not_exists(index(:products, [:deleted_at]))
  end
end
