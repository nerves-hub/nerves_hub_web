defmodule NervesHub.Repo.Migrations.CreateOrgRoles do
  use Ecto.Migration

  def change() do
    create table(:org_roles) do
      add(:org_id, references(:orgs), null: false)
      add(:name, :citext, null: false)
      add(:description, :string)
      add(:permissions, {:array, :string}, null: false, default: [])
      add(:deleted_at, :utc_datetime)

      timestamps()
    end

    create(index(:org_roles, [:org_id]))

    create(
      unique_index(:org_roles, [:org_id, :name],
        name: :org_roles_org_id_name_index,
        where: "deleted_at IS NULL"
      )
    )

    # The target of the composite foreign keys below. Referencing `org_id` as
    # well as `id` is what stops a member or invite being given another
    # organization's role.
    create(unique_index(:org_roles, [:id, :org_id]))

    alter table(:org_users) do
      add(:org_role_id, references(:org_roles, with: [org_id: :org_id]))
    end

    create(index(:org_users, [:org_role_id]))

    # Existing rows all have a built-in role, and some old ones may have none,
    # so the database only rules out holding both kinds at once. The changesets
    # require one of them.
    create(constraint(:org_users, :org_users_one_kind_of_role, check: "role IS NULL OR org_role_id IS NULL"))

    alter table(:invites) do
      add(:org_role_id, references(:org_roles, with: [org_id: :org_id]))
    end

    create(index(:invites, [:org_role_id]))

    create(constraint(:invites, :invites_one_kind_of_role, check: "role IS NULL OR org_role_id IS NULL"))
  end
end
