defmodule NervesHubWebCore.Repo.Migrations.AddDerToDeviceCertificates do
  use Ecto.Migration

  def change do
    alter table(:device_certificates) do
      add :der, :binary
    end
  end
end
