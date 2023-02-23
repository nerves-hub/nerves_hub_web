defmodule NervesHub.Repo.Migrations.FixUniqueIndices do
  use Ecto.Migration

  def change do
    create(unique_index(:products, [:tenant_id, :name], name: :products_tenant_id_name_index))

    create(
      unique_index(
        :user_certificates,
        [:user_id, :serial],
        name: :user_certificates_user_id_serial_index
      )
    )
  end
end
