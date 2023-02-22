defmodule NervesHubWebCore.Repo.Migrations.AddSizeToFirmware do
  use Ecto.Migration

  def change do
    alter table(:firmwares) do
      add(:size, :integer)
    end
  end
end
