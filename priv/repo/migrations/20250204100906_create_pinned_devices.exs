defmodule NervesHub.Repo.Migrations.CreatePinnedDevices do
  use Ecto.Migration

  def change do
    create table(:pinned_devices) do
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:device_id, references(:devices, on_delete: :delete_all))

      timestamps(updated_at: false)
    end
  end
end
