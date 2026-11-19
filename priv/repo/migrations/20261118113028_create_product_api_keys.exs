defmodule NervesHub.Repo.Migrations.CreateProductApiKeys do
  use Ecto.Migration

  def change() do
    create table(:product_api_keys) do
      add(:product_id, references(:products, on_delete: :delete_all), null: false)

      # The product's org, copied here so the composite foreign key below can
      # refuse a role from another organization. Never set from user input.
      add(:org_id, references(:orgs), null: false)

      # Who made the key, for the settings page. The key does not act as this
      # person and keeps working after they leave, so losing the user only
      # loses the label.
      add(:created_by_id, references(:users, on_delete: :nilify_all))

      # A key holds a built-in `role` or a custom `org_role`, never both, the
      # same way a member does. Referencing `org_id` as well as `id` is what
      # stops a key being given another organization's role.
      add(:org_role_id, references(:org_roles, with: [org_id: :org_id]))
      add(:role, :string)

      add(:name, :string, null: false)

      # SHA-512 of the key's random part. The key itself is shown once, when it
      # is created, and never stored.
      add(:token_hash, :binary, null: false)

      add(:last_used_at, :utc_datetime)
      add(:deactivated_at, :utc_datetime)

      timestamps()
    end

    create(
      constraint(:product_api_keys, :product_api_keys_one_kind_of_role, check: "role IS NULL OR org_role_id IS NULL")
    )

    # `admin` is left out on purpose. What it adds over `manage` is running the
    # organization, and a key only ever works inside one product. Custom roles
    # can't hold those permissions either; see `NervesHub.Accounts.Permissions`.
    create(
      constraint(:product_api_keys, :product_api_keys_role_is_view_or_manage,
        check: "role IS NULL OR role IN ('view', 'manage')"
      )
    )

    # What every authenticated request looks a key up by.
    create(unique_index(:product_api_keys, [:token_hash]))

    create(index(:product_api_keys, [:product_id]))
    create(index(:product_api_keys, [:org_id]))
    create(index(:product_api_keys, [:created_by_id]))
    create(index(:product_api_keys, [:org_role_id]))
  end
end
