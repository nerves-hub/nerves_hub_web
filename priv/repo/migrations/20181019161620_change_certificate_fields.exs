defmodule NervesHub.Repo.Migrations.ChangeCertificateFields do
  use Ecto.Migration

  def change do
    rename(table(:device_certificates), :authority_key_id, to: :aki)
    rename(table(:user_certificates), :authority_key_id, to: :aki)

    alter table(:user_certificates) do
      add :ski, :binary
      remove :aki
      add :aki, :binary
    end

    alter table(:device_certificates) do
      add :ski, :binary
      remove :aki
      add :aki, :binary
    end
  end
end
