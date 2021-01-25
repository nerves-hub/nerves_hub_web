defmodule NervesHubWebCore.Devices.DeviceCertificate do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias NervesHubWebCore.Accounts.Org
  alias NervesHubWebCore.{Certificate, Devices, Repo}
  alias NervesHubWebCore.Devices.{Device, DeviceCertificate}

  @type t :: %__MODULE__{}

  @required_params [
    :org_id,
    :device_id,
    :serial,
    :aki,
    :not_after,
    :not_before,
    :der
  ]
  @optional_params [
    :ski,
    :last_used
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
    field(:fingerprint, :string)
    field(:public_key_fingerprint, :string)

    timestamps()
  end

  def changeset(%DeviceCertificate{} = device_certificate, params) do
    device_certificate
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> add_fingerprints()
    |> unique_constraint(:serial, name: :device_certificates_device_id_serial_index)
    |> unique_constraint(:fingerprint, name: :device_certificates_fingerprint_index)
    |> validate_aki()
  end

  def update_changeset(%DeviceCertificate{} = device_certificate, params) do
    device_certificate
    # Allowing the DER here is temporary while we backfill device connections
    |> cast(params, [:last_used, :der])
    |> remove_der_change_if_exists()
    |> add_fingerprints()
  end

  defp remove_der_change_if_exists(%{data: %{der: der}, changes: %{der: _}} = changeset)
       when is_binary(der) do
    # We only want to save the DER once.
    # If it already exists on the record, ignore it
    # TODO: Remove this updatable field when confident enough have been captured
    delete_change(changeset, :der)
  end

  defp remove_der_change_if_exists(changeset), do: changeset

  defp add_fingerprints(changeset) do
    case {get_change(changeset, :der), changeset.valid?} do
      {der, true} when is_binary(der) ->
        otp_cert = X509.Certificate.from_der!(der)

        changeset
        |> put_change(:fingerprint, Certificate.fingerprint(otp_cert))
        |> put_change(:public_key_fingerprint, Certificate.public_key_fingerprint(otp_cert))
        |> validate_pk_fingerprint()

      _ ->
        changeset
    end
  end

  defp validate_pk_fingerprint(changeset) do
    device_id = get_field(changeset, :device_id)
    pk_fp = get_field(changeset, :public_key_fingerprint)

    from(c in DeviceCertificate,
      where: c.public_key_fingerprint == ^pk_fp and c.device_id != ^device_id,
      select: count()
    )
    |> Repo.one()
    |> case do
      0 ->
        changeset

      _ ->
        add_error(
          changeset,
          :public_key_fingerprint,
          "public key already associated with another device"
        )
    end
  end

  defp validate_aki(%{changes: %{aki: aki}} = changeset) do
    org_id = get_field(changeset, :org_id)

    case Devices.get_ca_certificate_by_ski(aki) do
      {:ok, %{org_id: ^org_id}} ->
        changeset

      {:ok, _ca} ->
        add_error(changeset, :org, "Signer CA registered with another org")

      _ ->
        # TODO: Add this - But lots of tests would need fixing first
        #   add_error(changeset, :org, "Signer CA must be registered first")
        changeset
    end
  end

  # AKI is missing and already reported
  defp validate_aki(changeset), do: changeset
end
