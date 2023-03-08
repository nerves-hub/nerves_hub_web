defmodule NervesHub.Repo.Migrations.RenameHealthyOnDevices do
  use Ecto.Migration

  def change do
    rename(table(:devices), :healthy, to: :updates_enabled)
  end
end
