defmodule NervesHub.Repo.Migrations.AddProgressAndUpdatedAtToInflightUpdates do
  use Ecto.Migration

  def change() do
    alter table(:inflight_updates) do
      add(:progress, :integer)
      add(:updated_at, :utc_datetime, null: false, default: fragment("NOW()"))
    end
  end
end
