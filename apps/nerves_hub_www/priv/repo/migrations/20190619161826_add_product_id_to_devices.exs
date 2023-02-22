defmodule NervesHubWebCore.Repo.Migrations.AddProductIdToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:product_id, references(:products))
    end
  end
end
