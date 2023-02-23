defmodule NervesHub.Repo.Migrations.RemoveJitpProductUniqueness do
  use Ecto.Migration

  def change do
    drop unique_index(:jitp, [:product_id])
  end
end
