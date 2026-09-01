defmodule NervesHub.Devices.ComponentTopology do
  @moduledoc """
  The component topology a device last reported.

  The topology describes what the device is made of and what talks to it:
  assemblies of components, networks of peers, and for each part the health
  metric/metadata keys that belong to it plus the actions and modes it exposes.
  See `NervesHub.Devices.Components` for the shape that is kept.

  One row per device, replaced on every report — this is a picture of the
  present, not a history.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device

  @type t() :: %__MODULE__{}

  # A ceiling rather than an expectation: a topology is identifiers, labels and
  # key names, so even a hub fronting hundreds of peers stays well under this.
  # It bounds what a malformed or hostile device can make us store.
  @max_topology_bytes 65_536

  schema "device_component_topologies" do
    belongs_to(:device, Device)

    field(:topology, :map, default: %{})
    field(:reported_at, :utc_datetime)

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = component_topology, params) do
    component_topology
    |> cast(params, [:device_id, :topology, :reported_at])
    |> validate_required([:device_id, :topology, :reported_at])
    |> validate_topology_size()
    |> foreign_key_constraint(:device_id)
    |> unique_constraint(:device_id, name: :device_component_topologies_device_id_index)
  end

  @doc """
  The largest topology that will be accepted, in bytes when encoded.
  """
  def max_topology_bytes(), do: @max_topology_bytes

  # The topology is written from a device-supplied payload, so it needs a
  # ceiling. Encoding is the only honest way to measure it, and a map that will
  # not encode cannot be stored in a jsonb column either.
  defp validate_topology_size(changeset) do
    case get_change(changeset, :topology) do
      nil ->
        changeset

      topology ->
        case Jason.encode(topology) do
          {:ok, encoded} when byte_size(encoded) <= @max_topology_bytes ->
            changeset

          {:ok, _encoded} ->
            add_error(changeset, :topology, "must be at most %{count} bytes when encoded", count: @max_topology_bytes)

          {:error, _} ->
            add_error(changeset, :topology, "must be JSON encodable")
        end
    end
  end
end
