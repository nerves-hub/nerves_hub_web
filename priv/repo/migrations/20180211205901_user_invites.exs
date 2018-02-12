defmodule Beamware.Repo.Migrations.UserInvites do
  use Ecto.Migration

  def change do
    create table(:invites) do
      add(:tenant_id, references(:tenants), null: false)
      add(:name, :string, null: false)
      add(:email, :string, null: false)
      add(:token, :uuid, null: false)
      add(:accepted, :boolean, null: false, default: false)

      timestamps()
    end
  end
end
