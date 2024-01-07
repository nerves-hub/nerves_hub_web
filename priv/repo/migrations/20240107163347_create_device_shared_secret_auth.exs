defmodule NervesHub.Repo.Migrations.CreateDeviceSharedSecretAuth do
  use Ecto.Migration

  def change do
    create table(:device_shared_secret_auths) do
      add(:device_id, references(:devices), null: false)
      add(:product_shared_secret_auth_id, references(:product_shared_secret_auth))

      add(:key, :string, null: false)
      add(:secret, :string, null: false)

      add(:deactivated_at, :utc_datetime)

      timestamps()
    end

    create index(:device_shared_secret_auths, [:key], unique: true)
    create index(:device_shared_secret_auths, [:secret], unique: true)
  end
end
