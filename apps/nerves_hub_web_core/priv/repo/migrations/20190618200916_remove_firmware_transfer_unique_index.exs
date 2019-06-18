defmodule NervesHubWebCore.Repo.Migrations.RemoveFirmwareTransferUniqueIndex do
  use Ecto.Migration

  def change do
    drop(index(:firmware_transfers, [:unique]))
  end
end
