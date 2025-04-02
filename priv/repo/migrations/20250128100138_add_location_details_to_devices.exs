defmodule NervesHub.Repo.Migrations.AddLocationDetailsToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:custom_location_coordinates, {:array, :float})
    end
  end
end
