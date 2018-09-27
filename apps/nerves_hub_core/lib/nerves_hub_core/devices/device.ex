defmodule NervesHubCore.Devices.Device do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHubCore.Repo
  alias NervesHubCore.Accounts
  alias NervesHubCore.Accounts.Org
  alias NervesHubCore.Firmwares.Firmware
  alias NervesHubCore.Devices.DeviceCertificate

  alias __MODULE__

  @type t :: %__MODULE__{}
  @optional_params [
    :last_known_firmware_id,
    :last_communication,
    :description,
    :tags
  ]
  @required_params [:org_id, :identifier]

  schema "devices" do
    belongs_to(:org, Org)
    belongs_to(:last_known_firmware, Firmware)

    has_many(:device_certificates, DeviceCertificate, on_delete: :delete_all)

    field(:identifier, :string)
    field(:description, :string)
    field(:last_communication, :utc_datetime)
    field(:tags, {:array, :string})

    timestamps()
  end

  def changeset(%Device{} = device, params) do
    device
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> validate_length(:tags, min: 1)
    |> validate_device_limit()
    |> unique_constraint(:identifier, name: :devices_org_id_identifier_index)
  end

  defp validate_device_limit(%Ecto.Changeset{changes: %{org_id: org_id}} = cs) do
    if too_many_devices?(org_id) do
      cs |> add_error(:org, "device limit reached")
    else
      cs
    end
  end

  defp validate_device_limit(%Ecto.Changeset{} = cs) do
    cs
  end

  defp too_many_devices?(org_id) do
    device_count =
      from(d in Device, where: d.org_id == ^org_id, select: count(d.id))
      |> Repo.one()

    %{devices: limit} = Accounts.get_org_limit_by_org_id(org_id)
    device_count + 1 > limit
  end

  def with_firmware(device_query) do
    device_query
    |> preload(:last_known_firmware)
  end

  def with_org(device_query) do
    device_query
    |> preload(:org)
  end
end
