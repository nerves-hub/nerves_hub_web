defmodule NervesHub.Repo.Migrations.AddCertificateInfo do
  use Ecto.Migration

  def change do
    alter table(:device_certificates) do
      add(:authority_key_id, :string)
    end

    alter table(:user_certificates) do
      add(:authority_key_id, :string)
      add(:not_before, :utc_datetime)
      add(:not_after, :utc_datetime)
    end
  end
end
