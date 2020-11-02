defmodule NervesHubWebCore.Repo.Migrations.AddPatchableFlagToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add(:delta_updatable, :boolean, default: true)
    end
  end
end
