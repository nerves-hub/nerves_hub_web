defmodule NervesHub.Repo.Migrations.AddCheckExpirationToCaCerts do
  use Ecto.Migration

  def change do
    alter table(:ca_certificates) do
      add :check_expiration, :boolean
    end
  end
end
