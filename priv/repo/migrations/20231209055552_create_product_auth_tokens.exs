defmodule NervesHub.Repo.Migrations.CreateProductAuthTokens do
  use Ecto.Migration

  def change do
    create table(:product_auth_tokens) do
      add(:product_id, references(:products), null: false)

      add(:access_id, :string, null: false)
      add(:secret, :string, null: false)

      add(:deactivated_at, :utc_datetime)

      timestamps()
    end

    create index(:product_auth_tokens, [:access_id], unique: true)
    create index(:product_auth_tokens, [:secret], unique: true)
  end
end
