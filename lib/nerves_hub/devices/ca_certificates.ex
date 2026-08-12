defmodule NervesHub.Devices.CACertificates do
  @moduledoc """
  Context for managing CA (certificate authority) certificates.

  CA certificates are registered per organization and used to authenticate
  devices (and to support just-in-time provisioning) during the TLS handshake.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.Org
  alias NervesHub.Certificate
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Repo

  @spec create_ca_certificate(Org.t(), map()) ::
          {:ok, CACertificate.t()}
          | {:error, Changeset.t()}
  def create_ca_certificate(%Org{} = org, params) do
    org
    |> Ecto.build_assoc(:ca_certificates)
    |> CACertificate.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, ca_certificate} ->
        {:ok, Repo.preload(ca_certificate, jitp: :product)}

      err ->
        err
    end
  end

  @spec create_ca_certificate_from_x509(Org.t(), X509.Certificate.t(), binary() | nil) ::
          {:ok, CACertificate.t()} | {:error, Ecto.Changeset.t()}
  def create_ca_certificate_from_x509(%Org{} = org, otp_cert, description \\ nil) when is_tuple(otp_cert) do
    {not_before, not_after} = Certificate.get_validity(otp_cert)

    params = %{
      serial: Certificate.get_serial_number(otp_cert),
      aki: Certificate.get_aki(otp_cert),
      ski: Certificate.get_ski(otp_cert),
      not_before: not_before,
      not_after: not_after,
      der: X509.Certificate.to_der(otp_cert),
      description: description
    }

    create_ca_certificate(org, params)
  end

  def get_ca_certificates(%Org{id: org_id}) do
    from(ca in CACertificate, where: ca.org_id == ^org_id, preload: [jitp: :product])
    |> Repo.all()
  end

  @spec get_ca_certificate_by_aki(binary) :: {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_aki(aki) do
    from(CACertificate, where: [aki: ^aki], preload: [jitp: :product])
    |> Repo.fetch()
  end

  @spec known_ca_ski?(binary) :: boolean()
  def known_ca_ski?(ski) do
    CACertificate
    |> where(ski: ^ski)
    |> Repo.exists?()
  end

  @spec get_ca_certificate_by_ski(binary) :: {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_ski(ski) do
    CACertificate
    |> join(:left, [cac], jitp in assoc(cac, :jitp))
    |> join(:left, [_cac, jitp], p in assoc(jitp, :product))
    |> where([cac], cac.ski == ^ski)
    |> preload([_cac, jitp, p], jitp: {jitp, product: p})
    |> Repo.fetch()
  end

  @spec get_ca_certificate_by_serial(binary) :: {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_serial(serial) do
    from(CACertificate, where: [serial: ^serial], preload: [jitp: :product])
    |> Repo.fetch()
  end

  @spec get_ca_certificate_by_org_and_serial(Org.t(), binary) ::
          {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_org_and_serial(%Org{id: org_id}, serial) do
    from(
      ca in CACertificate,
      where: ca.serial == ^serial and ca.org_id == ^org_id,
      preload: [jitp: :product]
    )
    |> Repo.fetch()
  end

  def update_ca_certificate(%CACertificate{} = certificate, params) do
    certificate
    |> CACertificate.update_changeset(params)
    |> Repo.update()
  end

  def delete_ca_certificate(%CACertificate{} = ca_certificate) do
    Repo.delete(ca_certificate)
  end
end
