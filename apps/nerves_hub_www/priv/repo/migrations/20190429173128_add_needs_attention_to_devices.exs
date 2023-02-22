defmodule NervesHubWebCore.Repo.Migrations.AddNeedsAttentionToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:healthy, :boolean, default: true)
    end
  end
end
