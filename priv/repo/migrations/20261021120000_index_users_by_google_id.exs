defmodule NervesHub.Repo.Migrations.IndexUsersByGoogleId do
  use Ecto.Migration

  def change() do
    create(unique_index(:users, [:google_id], where: "deleted_at IS NULL"))
  end
end
