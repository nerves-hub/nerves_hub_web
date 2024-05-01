defmodule NervesHub.Repo.Migrations.CreateCommands do
  use Ecto.Migration

  def change do
    create table(:commands) do
      add(:product_id, references(:products), null: false)
      add(:name, :string, null: false)
      add(:text, :text, null: false)

      timestamps()
    end
  end
end
