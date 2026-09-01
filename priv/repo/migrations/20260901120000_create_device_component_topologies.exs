defmodule NervesHub.Repo.Migrations.CreateDeviceComponentTopologies do
  @moduledoc """
  One row per device holding the component topology the device last reported
  through the `components` extension: assemblies of components and networks of
  peers, with the metric/metadata keys, actions and modes each part exposes.

  A single jsonb document rather than a table per entity: the topology is
  replaced wholesale on every report (it describes what the device *is*, not a
  history), is read as a whole to render the device page, and its shape is
  device-defined so columns would only ossify it.
  """

  use Ecto.Migration

  def change() do
    create table(:device_component_topologies) do
      add(:device_id, references(:devices, on_delete: :delete_all), null: false)
      add(:topology, :map, null: false, default: %{})
      add(:reported_at, :utc_datetime, null: false)

      timestamps()
    end

    # One topology per device; reports replace it.
    create(unique_index(:device_component_topologies, [:device_id], name: :device_component_topologies_device_id_index))
  end
end
