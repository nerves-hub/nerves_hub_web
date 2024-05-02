defmodule NervesHub.Repo.Migrations.CreateScripts do
  use Ecto.Migration

  def change do
    create table(:scripts) do
      add(:product_id, references(:products), null: false)
      add(:name, :string, null: false)
      add(:text, :text, null: false)

      timestamps()
    end
  end
end
