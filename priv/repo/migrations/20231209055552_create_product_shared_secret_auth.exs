defmodule NervesHub.Repo.Migrations.CreateProductSharedSecretAuth do
  use Ecto.Migration

  def change do
    create table(:product_shared_secret_auth) do
      add(:product_id, references(:products), null: false)

      add(:key, :string, null: false)
      add(:secret, :string, null: false)

      add(:deactivated_at, :utc_datetime)

      timestamps()
    end

    create index(:product_shared_secret_auth, [:key], unique: true)
    create index(:product_shared_secret_auth, [:secret], unique: true)
  end
end
