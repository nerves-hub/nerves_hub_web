defmodule NervesHubWebCore.Repo.Migrations.DevicePlatformArchitectureRequired do
  use Ecto.Migration

  def up do
    alter table(:devices) do
      modify :platform, :string, null: false
      modify :architecture, :string, null: false
    end
  end

  def down do
    alter table(:devices) do
      modify :platform, :string, null: true
      modify :architecture, :string, null: true
    end
  end
end
