defmodule NervesHub.Devices.Certificates do
  @moduledoc """
  Context for managing device certificates.

  Device certificates are used to authenticate a device during the TLS
  handshake and to look a device up from a presented X.509 certificate.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Certificate
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Repo

  @spec create_device_certificate(Device.t(), map() | X509.Certificate.t()) ::
          {:ok, DeviceCertificate.t()}
          | {:error, Changeset.t()}
  def create_device_certificate(%Device{} = device, otp_cert) when is_tuple(otp_cert) do
    {nb, na} = Certificate.get_validity(otp_cert)

    params = %{
      aki: Certificate.get_aki(otp_cert),
      der: Certificate.to_der(otp_cert),
      not_after: na,
      not_before: nb,
      serial: Certificate.get_serial_number(otp_cert),
      ski: Certificate.get_ski(otp_cert)
    }

    create_device_certificate(device, params)
  end

  def create_device_certificate(%Device{} = device, params) do
    params = Map.put(params, :org_id, device.org_id)

    changeset =
      device
      |> Ecto.build_assoc(:device_certificates)
      |> DeviceCertificate.changeset(params)

    case Repo.insert(changeset) do
      {:ok, device_certificate} ->
        :telemetry.execute([:nerves_hub, :device_certificates, :created], %{count: 1})

        {:ok, device_certificate}

      {:error, error} ->
        {:error, error}
    end
  end

  def has_device_certificates?(%Device{} = device) do
    DeviceCertificate
    |> join(:inner, [dc], d in assoc(dc, :device))
    |> where([_dc, d], d.id == ^device.id)
    |> Repo.exists?()
  end

  def get_device_certificates(%Device{} = device) do
    DeviceCertificate
    |> join(:inner, [dc], d in assoc(dc, :device))
    |> where([_dc, d], d.id == ^device.id)
    |> Repo.all()
  end

  @doc """
  Preloads a device's certificates. Pass `force: true` to reload them.
  """
  def preload_device_certificates(%Device{} = device, opts \\ []) do
    Repo.preload(device, :device_certificates, opts)
  end

  @spec get_device_by_certificate(DeviceCertificate.t()) ::
          {:ok, Device.t()} | {:error, :not_found}
  def get_device_by_certificate(%DeviceCertificate{device: %Ecto.Association.NotLoaded{}} = cert) do
    Repo.preload(cert, :device)
    |> get_device_by_certificate()
  end

  def get_device_by_certificate(%DeviceCertificate{device: %Device{} = device}), do: {:ok, Repo.preload(device, :org)}

  def get_device_by_certificate(_), do: {:error, :not_found}

  def get_device_by_x509(cert) do
    fingerprint = Certificate.fingerprint(cert)

    Device
    |> join(:inner, [d], p in assoc(d, :product))
    |> join(:inner, [d], dc in assoc(d, :device_certificates))
    |> where([_, _, dc], dc.fingerprint == ^fingerprint)
    |> preload([_d, p], product: p)
    |> Repo.fetch()
  end

  def get_device_certificate_by_x509(cert) do
    fingerprint = Certificate.fingerprint(cert)

    DeviceCertificate
    |> where(fingerprint: ^fingerprint)
    |> join(:inner, [dc], d in assoc(dc, :device))
    |> preload([_dc, d], device: d)
    |> Repo.fetch()
  end

  def get_device_by_public_key(otp_cert) do
    pk_fingerprint = Certificate.public_key_fingerprint(otp_cert)

    Device
    |> join(:inner, [d], dc in assoc(d, :device_certificates))
    |> where([_d, dc], dc.public_key_fingerprint == ^pk_fingerprint)
    |> Repo.one()
  end

  @spec get_device_certificate_by_device_and_serial(Device.t(), binary) ::
          {:ok, DeviceCertificate.t()} | {:error, any()}
  def get_device_certificate_by_device_and_serial(%Device{id: device_id}, serial) do
    query =
      from(
        dc in DeviceCertificate,
        where: dc.serial == ^serial and dc.device_id == ^device_id
      )

    query
    |> Repo.fetch()
  end

  def update_device_certificate(%DeviceCertificate{} = certificate, params) do
    certificate
    |> DeviceCertificate.update_changeset(params)
    |> Repo.update()
  end

  @spec delete_device_certificate(DeviceCertificate.t()) ::
          {:ok, DeviceCertificate.t()}
          | {:error, Changeset.t()}
  def delete_device_certificate(%DeviceCertificate{} = device_certificate) do
    Repo.delete(device_certificate)
  end
end
