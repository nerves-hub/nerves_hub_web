defmodule NervesHub.Repo.Migrations.AddProgressAndUpdatedAtToInflightUpdates do
  use Ecto.Migration

  def change() do
    alter table(:inflight_updates) do
      add(:progress, :integer)
      timestamps(inserted_at: false)
    end
  end
end
