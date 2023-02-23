defmodule NervesHub.Repo.Migrations.DeviceCertificateAllowLinSki do
  use Ecto.Migration

  def change do
    alter table(:device_certificates) do
      modify :ski, :binary, null: true
    end
  end
end
