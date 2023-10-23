defmodule NervesHub.Repo.Migrations.CreateArchives do
  use Ecto.Migration

  def change do
    create table(:archives) do
      add(:product_id, references(:products), null: false)
      add(:org_key_id, references(:org_keys), null: false)

      add(:size, :integer, null: false)

      add(:architecture, :string, null: false)
      add(:author, :string)
      add(:description, :text)
      add(:misc, :text)
      add(:platform, :string, null: false)
      add(:uuid, :uuid, null: false)
      add(:version, :string, null: false)
      add(:vcs_identifier, :string)

      timestamps()
    end

    create index(:archives, [:product_id, :uuid], unique: true)
  end
end
