defmodule NervesHub.Repo.Migrations.AddLastUsedToCertificates do
  use Ecto.Migration

  def change do
    alter table(:user_certificates) do
      add :last_used, :utc_datetime
    end

    alter table(:ca_certificates) do
      add :last_used, :utc_datetime
    end

    alter table(:device_certificates) do
      add :last_used, :utc_datetime
    end
  end
end
