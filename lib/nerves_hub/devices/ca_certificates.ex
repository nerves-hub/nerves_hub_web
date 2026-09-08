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
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Products.Product
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

  @doc """
  Counts the devices in the org whose certificates were signed by each of its
  CAs, keyed by the CA's SKI.

  A device certificate records its signer's key id as its AKI, so a CA's SKI is
  what ties the two together. Devices with more than one certificate from the
  same CA are only counted once, and soft deleted devices are left out so the
  count matches what the device list shows by default.
  """
  @spec device_counts_by_ski(Org.t()) :: %{binary() => non_neg_integer()}
  def device_counts_by_ski(%Org{id: org_id}) do
    from(dc in DeviceCertificate,
      join: d in assoc(dc, :device),
      where: dc.org_id == ^org_id,
      where: is_nil(d.deleted_at),
      group_by: dc.aki,
      select: {dc.aki, count(dc.device_id, :distinct)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The products which have devices signed by the CA, along with each product's
  device count, ordered by product name.

  The device list is scoped to a single product, so this is what a "devices
  using this CA" link has to be broken down by.
  """
  @spec device_counts_by_product(CACertificate.t()) ::
          [%{product: Product.t(), device_count: non_neg_integer()}]
  def device_counts_by_product(%CACertificate{ski: ski, org_id: org_id}) do
    from(dc in DeviceCertificate,
      join: d in assoc(dc, :device),
      join: p in assoc(d, :product),
      where: dc.aki == ^ski,
      where: dc.org_id == ^org_id,
      where: is_nil(d.deleted_at),
      where: is_nil(p.deleted_at),
      group_by: p.id,
      order_by: p.name,
      select: %{product: p, device_count: count(d.id, :distinct)}
    )
    |> Repo.all()
  end

  @doc """
  The org's CAs which signed a certificate held by a device in the product,
  ordered by description then serial.

  Built from the devices rather than from the org's CA list so the device list's
  signer CA filter only offers CAs that can actually match something.
  """
  @spec signer_cas_for_product(pos_integer()) :: [CACertificate.t()]
  def signer_cas_for_product(product_id) do
    from(ca in CACertificate,
      join: dc in DeviceCertificate,
      on: dc.aki == ca.ski,
      join: d in assoc(dc, :device),
      where: d.product_id == ^product_id,
      where: ca.org_id == d.org_id,
      distinct: true,
      order_by: [asc: ca.description, asc: ca.serial],
      select: ca
    )
    |> Repo.all()
  end

  @doc """
  The org's CAs matching the given SKIs, keyed by SKI.

  Scoped to the org so a certificate signed by another org's CA reads as
  unknown rather than exposing that CA.
  """
  @spec by_ski(Org.t() | pos_integer(), [binary()]) :: %{binary() => CACertificate.t()}
  def by_ski(%Org{id: org_id}, skis), do: by_ski(org_id, skis)

  def by_ski(org_id, skis) when is_integer(org_id) do
    skis = Enum.reject(skis, &is_nil/1)

    from(ca in CACertificate, where: ca.org_id == ^org_id and ca.ski in ^skis)
    |> Repo.all()
    |> Map.new(&{&1.ski, &1})
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
