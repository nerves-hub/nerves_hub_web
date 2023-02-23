defmodule NervesHub.Repo.Migrations.AddDescriptionToCaCertificates do
  use Ecto.Migration

  def change do
    alter table(:ca_certificates) do
      add(:description, :string)
    end
  end
end
