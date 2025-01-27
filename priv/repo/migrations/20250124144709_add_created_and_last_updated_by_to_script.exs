defmodule NervesHub.Repo.Migrations.AddCreatedAndLastUpdatedByToScript do
  use Ecto.Migration

  def change do
    alter table(:scripts) do
      add(:created_by_id, references(:users))
      add(:last_updated_by_id, references(:users))
    end
  end
end
