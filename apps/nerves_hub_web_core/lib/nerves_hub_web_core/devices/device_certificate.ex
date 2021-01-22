defmodule NervesHubWebCore.Devices.DeviceCertificate do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHubWebCore.Accounts.Org
  alias NervesHubWebCore.Devices.{Device, DeviceCertificate}

  @type t :: %__MODULE__{}

  @required_params [
    :org_id,
    :device_id,
    :serial,
    :aki,
    :not_after,
    :not_before
    # TODO: Require this field once DERs have been captured in field
    # :der
  ]
  @optional_params [
    :ski,
    :last_used,
    :der
  ]

  schema "device_certificates" do
    belongs_to(:device, Device)
    belongs_to(:org, Org)

    field(:serial, :string)
    field(:aki, :binary)
    field(:ski, :binary)
    field(:not_before, :utc_datetime)
    field(:not_after, :utc_datetime)
    field(:last_used, :utc_datetime)
    field(:der, :binary)

    timestamps()
  end

  def changeset(%DeviceCertificate{} = device_certificate, params) do
    device_certificate
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:serial, name: :device_certificates_device_id_serial_index)
  end

  def update_changeset(%DeviceCertificate{} = device_certificate, params) do
    device_certificate
    # Allowing the DER here is temporary while we backfill device connections
    |> cast(params, [:last_used, :der])
    |> remove_der_change_if_exists()
  end

  defp remove_der_change_if_exists(%{data: %{der: der}, changes: %{der: _}} = changeset)
       when is_binary(der) do
    # We only want to save the DER once.
    # If it already exists on the record, ignore it
    # TODO: Remove this updatable field when confident enough have been captured
    delete_change(changeset, :der)
  end

  defp remove_der_change_if_exists(changeset), do: changeset
end
