defmodule NervesHubWebCore.Repo.Migrations.AddJitpToCaCertificates do
  use Ecto.Migration

  def change do
    create table(:jitp) do
      add :product_id, references(:products, null: false)
      add :tags, {:array, :string}
      add :description, :string
      timestamps()
    end

    create unique_index(:jitp, [:product_id])

    alter table(:ca_certificates) do
      add :jitp_id, references(:jitp, on_delete: :nilify_all)
    end

    create unique_index(:ca_certificates, [:jitp_id])
  end


end
