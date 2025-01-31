defmodule NervesHub.Devices do
  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Certificate
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Deployments.Orchestrator
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Devices.Filtering
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.SharedSecretAuth
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Extensions
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.TaskSupervisor, as: Tasks

  @min_fwup_delta_updatable_version ">=1.10.0"

  def get_device(device_id) when is_integer(device_id) do
    Repo.get(Device, device_id)
  end

  def get_active_device(filters) do
    Device
    |> Repo.exclude_deleted()
    |> join(:inner, [d], p in assoc(d, :product))
    |> preload([_d, p], product: p)
    |> Repo.get_by(filters)
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_devices_by_org_id_and_product_id(org_id, product_id) do
    Device
    |> where([d], d.org_id == ^org_id)
    |> where([d], d.product_id == ^product_id)
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  def get_devices_by_org_id_and_product_id(org_id, product_id, opts) do
    {entries, _pager} = get_devices_by_org_id_and_product_id_with_pager(org_id, product_id, opts)
    entries
  end

  def get_devices_by_org_id_and_product_id_with_pager(org_id, product_id, opts) do
    pagination = Map.get(opts, :pagination, %{page: 1, page_size: 10})
    sorting = Map.get(opts, :sort, {:asc, :identifier})
    filters = Map.get(opts, :filters, %{})

    flop = %Flop{page: pagination[:page], page_size: pagination[:page_size]}

    Device
    |> where([d], d.org_id == ^org_id)
    |> where([d], d.product_id == ^product_id)
    |> join(:left, [d], o in assoc(d, :org))
    |> join(:left, [d, o], p in assoc(d, :product))
    |> join(:left, [d, o, p], dp in assoc(d, :deployment))
    |> join(:left, [d, o, p, dp], f in assoc(dp, :firmware))
    |> join(:left, [d, o, p, dp, f], lc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:left, [d, o, p, dp, f, lc], lh in assoc(d, :latest_health), as: :latest_health)
    |> Repo.exclude_deleted()
    |> sort_devices(sorting)
    |> Filtering.build_filters(filters)
    |> preload([d, o, p, dp, f, latest_connection: lc, latest_health: lh],
      org: o,
      product: p,
      deployment: {dp, firmware: f},
      latest_connection: lc,
      latest_health: lh
    )
    |> Flop.run(flop)
  end

  def get_device_count_by_org_id_and_product_id(org_id, product_id) do
    query =
      from(
        d in Device,
        select: count(d.id),
        where: d.org_id == ^org_id,
        where: d.product_id == ^product_id
      )

    query
    |> Repo.one!()
  end

  @spec filter(Product.t(), map()) :: %{
          entries: list(Device.t()),
          current_page: non_neg_integer(),
          page_size: non_neg_integer(),
          total_pages: non_neg_integer(),
          total_count: non_neg_integer()
        }
  def filter(product, opts) do
    pagination = Map.get(opts, :pagination, %{})
    sorting = Map.get(opts, :sort, {:asc, :identifier})
    filters = Map.get(opts, :filters, %{})

    flop = %Flop{page: pagination.page, page_size: pagination.page_size}

    Device
    |> where([d], d.product_id == ^product.id)
    |> Repo.exclude_deleted()
    |> join(:left, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:left, [d, dc], dh in assoc(d, :latest_health), as: :latest_health)
    |> preload([latest_connection: lc], latest_connection: lc)
    |> preload([latest_health: lh], latest_health: lh)
    |> Filtering.build_filters(filters)
    |> sort_devices(sorting)
    |> Flop.run(flop)
    |> then(fn {entries, meta} ->
      meta
      |> Map.take([
        :current_page,
        :page_size,
        :total_pages,
        :total_count
      ])
      |> Map.put(:entries, entries)
    end)
  end

  def get_minimal_device_location_by_product(product) do
    Device
    |> join(:inner, [d], dc in DeviceConnection, on: d.latest_connection_id == dc.id)
    |> where(product_id: ^product.id)
    |> select([d, dc], %{
      id: d.id,
      identifier: d.identifier,
      connection_status: dc.status,
      latitude: fragment("?->'location'->'latitude'", dc.metadata),
      longitude: fragment("?->'location'->'longitude'", dc.metadata),
      firmware_uuid: fragment("?->'uuid'", d.firmware_metadata)
    })
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  defp sort_devices(query, {:asc, :connection_last_seen_at}) do
    order_by(query, [latest_connection: latest_connection],
      desc_nulls_last: latest_connection.last_seen_at
    )
  end

  defp sort_devices(query, {:desc, :connection_last_seen_at}) do
    order_by(query, [latest_connection: latest_connection],
      asc_nulls_first: latest_connection.last_seen_at
    )
  end

  defp sort_devices(query, sort), do: order_by(query, [], ^sort)

  def get_device_count_by_org_id(org_id) do
    q =
      from(
        d in Device,
        where: d.org_id == ^org_id,
        select: count(d)
      )

    q
    |> Repo.exclude_deleted()
    |> Repo.one!()
  end

  def get_device_count_by_product_id(product_id) do
    Device
    |> where([d], d.product_id == ^product_id)
    |> Repo.exclude_deleted()
    |> select([d], count(d))
    |> Repo.one!()
  end

  defp device_by_org_query(org_id, device_id) do
    from(
      d in Device,
      where: d.org_id == ^org_id,
      where: d.id == ^device_id
    )
  end

  def get_device_by_org(%Org{id: org_id}, device_id) do
    device_by_org_query(org_id, device_id)
    |> Repo.exclude_deleted()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_by_identifier(identifier) do
    case Repo.get_by(Device, identifier: identifier) do
      nil ->
        {:error, :not_found}

      device ->
        {:ok, Repo.preload(device, [:org, :product, deployment: [:firmware]])}
    end
  end

  @spec get_device_by_identifier(Org.t(), String.t()) :: {:ok, Device.t()} | {:error, :not_found}
  def get_device_by_identifier(org, identifier, preload_assoc \\ nil)
      when is_binary(identifier) do
    get_device_by_identifier_query(org, identifier, preload_assoc)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  @spec get_device_by_identifier!(Org.t(), String.t()) :: Device.t()
  def get_device_by_identifier!(org, identifier, preload_assoc \\ nil)
      when is_binary(identifier) do
    get_device_by_identifier_query(org, identifier, preload_assoc)
    |> Repo.one!()
  end

  defp get_device_by_identifier_query(%Org{id: org_id}, identifier, preload_assoc) do
    Device
    |> where(identifier: ^identifier)
    |> where(org_id: ^org_id)
    |> join(:left, [d], o in assoc(d, :org))
    |> join(:left, [d], dp in assoc(d, :deployment))
    |> join_and_preload(preload_assoc)
    |> preload([d, o, dp], org: o, deployment: dp)
  end

  defp join_and_preload(query, assocs) when is_list(assocs) do
    Enum.reduce(assocs, query, fn assoc, q ->
      join_and_preload(q, assoc)
    end)
  end

  defp join_and_preload(query, nil), do: query

  defp join_and_preload(query, :device_certificates) do
    query
    |> join(:left, [d], dc in assoc(d, :device_certificates), as: :device_certificates)
    |> preload([d, device_certificates: dc], device_certificates: dc)
  end

  defp join_and_preload(query, :latest_connection) do
    query
    |> join(:left, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
    |> preload([latest_connection: lc], latest_connection: lc)
  end

  defp join_and_preload(query, :latest_health) do
    query
    |> join(:left, [d], dh in assoc(d, :latest_health), as: :latest_health)
    |> preload([latest_health: lh], latest_health: lh)
  end

  def get_device_by_x509(cert) do
    fingerprint = NervesHub.Certificate.fingerprint(cert)

    Device
    |> join(:inner, [d], p in assoc(d, :product))
    |> join(:inner, [d], dc in assoc(d, :device_certificates))
    |> where([_, _, dc], dc.fingerprint == ^fingerprint)
    |> preload([_d, p], product: p)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      certificate -> {:ok, certificate}
    end
  end

  @spec get_shared_secret_auth(String.t()) ::
          {:ok, SharedSecretAuth.t()} | {:error, :not_found}
  def get_shared_secret_auth(key) do
    SharedSecretAuth
    |> join(:inner, [ssa], d in assoc(ssa, :device))
    |> where([ssa], ssa.key == ^key)
    |> where([ssa], is_nil(ssa.deactivated_at))
    |> where([_, d], is_nil(d.deleted_at))
    |> preload([:device, :product_shared_secret_auth])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      auth -> {:ok, auth}
    end
  end

  @spec create_shared_secret_auth(Device.t()) ::
          {:ok, SharedSecretAuth.t()} | {:error, Changeset.t()}
  @spec create_shared_secret_auth(Device.t(), map()) ::
          {:ok, SharedSecretAuth.t()} | {:error, Changeset.t()}
  def create_shared_secret_auth(device, attrs \\ %{}) do
    device
    |> SharedSecretAuth.create_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_or_create_device(Products.SharedSecretAuth.t(), String.t()) ::
          {:ok, Device.t()} | {:error, :not_found}
  def get_or_create_device(%Products.SharedSecretAuth{} = auth, identifier) do
    with {:error, :not_found} <-
           get_active_device(product_id: auth.product_id, identifier: identifier),
         {:ok, product} <-
           Products.get_product(auth.product_id) do
      create_device(%{
        org_id: product.org_id,
        product_id: product.id,
        identifier: identifier
      })
    else
      result ->
        result
    end
  end

  def get_device_by(filters) do
    Repo.get_by(Device, filters)
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_eligible_deployments(%Device{firmware_metadata: nil}), do: []

  def get_eligible_deployments(%Device{firmware_metadata: meta} = device) do
    from(
      d in Deployment,
      join: p in assoc(d, :product),
      on: [org_id: ^device.org_id, name: ^meta.product],
      join: f in assoc(d, :firmware),
      on: f.product_id == p.id,
      where: d.is_active,
      where: d.healthy,
      where: f.architecture == ^meta.architecture,
      where: f.platform == ^meta.platform,
      where: f.uuid != ^meta.uuid,
      preload: [firmware: f]
    )
    |> Repo.all()
    |> Enum.filter(fn dep -> matches_deployment?(device, dep) end)
  end

  def get_eligible_deployments(_), do: []

  @spec create_device(map) :: {:ok, Device.t()} | {:error, Changeset.t()}
  def create_device(params) do
    %Device{}
    |> Device.changeset(params)
    |> Repo.insert()
    |> Repo.maybe_preload(:product)
  end

  def set_as_provisioned!(device) do
    device
    |> Device.changeset(%{status: :provisioned, first_seen_at: DateTime.utc_now()})
    |> Repo.update!()
  end

  def delete_device(%Device{} = device) do
    device_certificates_query = from(dc in DeviceCertificate, where: dc.device_id == ^device.id)
    changeset = Repo.soft_delete_changeset(device)

    Multi.new()
    |> Multi.delete_all(:device_certificates, device_certificates_query)
    |> Multi.update(:device, changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{device: device}} -> {:ok, device}
      error -> error
    end
  end

  def destroy_device(%Device{} = device) do
    Repo.delete(device)
  end

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

  @spec get_device_by_certificate(DeviceCertificate.t()) ::
          {:ok, Device.t()} | {:error, :not_found}
  def get_device_by_certificate(%DeviceCertificate{device: %Ecto.Association.NotLoaded{}} = cert) do
    Repo.preload(cert, :device)
    |> get_device_by_certificate()
  end

  def get_device_by_certificate(%DeviceCertificate{device: %Device{} = device}),
    do: {:ok, Repo.preload(device, :org)}

  def get_device_by_certificate(_), do: {:error, :not_found}

  def get_device_certificate_by_x509(cert) do
    fingerprint = NervesHub.Certificate.fingerprint(cert)

    DeviceCertificate
    |> where(fingerprint: ^fingerprint)
    |> join(:inner, [dc], d in assoc(dc, :device))
    |> preload([_dc, d], device: d)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      certificate -> {:ok, certificate}
    end
  end

  def get_device_by_public_key(otp_cert) do
    pk_fingerprint = NervesHub.Certificate.public_key_fingerprint(otp_cert)

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
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      device_certificate ->
        {:ok, device_certificate}
    end
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
  def create_ca_certificate_from_x509(%Org{} = org, otp_cert, description \\ nil)
      when is_tuple(otp_cert) do
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
    q = from(CACertificate, where: [aki: ^aki], preload: [jitp: :product])

    case Repo.one(q) do
      nil -> {:error, :not_found}
      ca_cert -> {:ok, ca_cert}
    end
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
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      ca_cert -> {:ok, ca_cert}
    end
  end

  @spec get_ca_certificate_by_serial(binary) :: {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_serial(serial) do
    q = from(CACertificate, where: [serial: ^serial], preload: [jitp: :product])

    case Repo.one(q) do
      nil -> {:error, :not_found}
      ca_cert -> {:ok, ca_cert}
    end
  end

  @spec get_ca_certificate_by_org_and_serial(Org.t(), binary) ::
          {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_org_and_serial(%Org{id: org_id}, serial) do
    query =
      from(
        ca in CACertificate,
        where: ca.serial == ^serial and ca.org_id == ^org_id,
        preload: [jitp: :product]
      )

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      ca_cert ->
        {:ok, ca_cert}
    end
  end

  def update_ca_certificate(%CACertificate{} = certificate, params) do
    certificate
    |> CACertificate.update_changeset(params)
    |> Repo.update()
  end

  def delete_ca_certificate(%CACertificate{} = ca_certificate) do
    Repo.delete(ca_certificate)
  end

  @type firmware_id :: binary()
  @type source_firmware_id() :: firmware_id()
  @type target_firmware_id() :: firmware_id()

  @spec get_device_firmware_for_delta_generation_by_product(binary()) ::
          list({source_firmware_id(), target_firmware_id()})
  def get_device_firmware_for_delta_generation_by_product(product_id) do
    Deployment
    |> where([dep], dep.product_id == ^product_id)
    |> join(:inner, [dep], dev in Device, on: dev.deployment_id == dep.id)
    |> join(:inner, [dep, dev], f in Firmware,
      on: f.uuid == fragment("d1.firmware_metadata->>'uuid'")
    )
    # Exclude the current firmware, we don't need to generate that one
    |> where([dep, dev, f], f.id != dep.firmware_id)
    |> select([dep, dev, f], {f.id, dep.firmware_id})
    |> Repo.all()
  end

  @spec get_device_firmware_for_delta_generation_by_deployment(binary()) ::
          list({source_firmware_id(), target_firmware_id()})
  def get_device_firmware_for_delta_generation_by_deployment(deployment_id) do
    Deployment
    |> where([dep], dep.id == ^deployment_id)
    |> join(:inner, [dep], dev in Device, on: dev.deployment_id == dep.id)
    |> join(:inner, [dep, dev], f in Firmware,
      on: f.uuid == fragment("d1.firmware_metadata->>'uuid'")
    )
    # Exclude the current firmware, we don't need to generate that one
    |> where([dep, dev, f], f.id != dep.firmware_id)
    |> select([dep, dev, f], {f.id, dep.firmware_id})
    |> Repo.all()
  end

  def update_firmware_metadata(device, nil) do
    {:ok, device}
  end

  def update_firmware_metadata(device, metadata) do
    DeviceTemplates.audit_firmware_metadata_updated(device)
    update_device(device, %{firmware_metadata: metadata})
  end

  def update_device(%Device{} = device, params, opts \\ []) do
    changeset = Device.changeset(device, params)

    case Repo.update(changeset) do
      {:ok, device} ->
        _ = maybe_broadcast(device, "devices/updated", opts)

        {:ok, device}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Fetch devices associated with a deployment for updating.

  Devices must be:
  - online
  - have automatic updates enabled
  - not currently updating
  - not be running the same firmware version associated with the deployment
  - not in the penalty box (based on `updates_blocked_until`)

  The list is ordered by current connection age. Devices that have been online longer
  are updated first.
  """
  @spec available_for_update(Deployment.t(), non_neg_integer()) :: [Device.t()]
  def available_for_update(deployment, count) do
    now = DateTime.utc_now(:second)

    Device
    |> join(:inner, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:inner, [d], dp in assoc(d, :deployment), as: :deployment)
    |> join(:inner, [deployment: dp], f in assoc(dp, :firmware),
      on: [product_id: ^deployment.product_id],
      as: :firmware
    )
    |> join(:left, [d], ifu in InflightUpdate, on: d.id == ifu.device_id, as: :inflight_update)
    |> where(deployment_id: ^deployment.id)
    |> where(updates_enabled: true)
    |> where([latest_connection: lc], lc.status == :connected)
    |> where([d], not is_nil(d.firmware_metadata))
    |> where([d, firmware: f], fragment("(? #>> '{\"uuid\"}') != ?", d.firmware_metadata, f.uuid))
    |> where([inflight_update: ifu], is_nil(ifu.id))
    |> where([d], is_nil(d.updates_blocked_until) or d.updates_blocked_until < ^now)
    |> order_by([latest_connection: lc], asc: lc.established_at)
    |> limit(^count)
    |> Repo.all()
  end

  @doc """
  Resolve an update for the device's deployment
  """
  @spec resolve_update(Device.t()) :: UpdatePayload.t()
  def resolve_update(%{status: :registered}), do: %UpdatePayload{update_available: false}

  def resolve_update(%{deployment_id: nil}), do: %UpdatePayload{update_available: false}

  def resolve_update(device) do
    {:ok, deployment} = Deployments.get_deployment_for_device(device)

    case verify_update_eligibility(device, deployment) do
      {:ok, _device} ->
        {:ok, url} = Firmwares.get_firmware_url(deployment.firmware)
        {:ok, meta} = Firmwares.metadata_from_firmware(deployment.firmware)

        %UpdatePayload{
          update_available: true,
          firmware_url: url,
          firmware_meta: meta,
          deployment: deployment,
          deployment_id: deployment.id
        }

      {:error, :deployment_not_active, _device} ->
        %UpdatePayload{update_available: false}

      {:error, :up_to_date, _device} ->
        %UpdatePayload{update_available: false}

      {:error, :updates_blocked, _device} ->
        %UpdatePayload{update_available: false}
    end
  end

  @spec delta_updatable?(
          source :: Firmware.t(),
          target :: Firmware.t(),
          Product.t(),
          fwup_version :: String.t()
        ) :: boolean()
  def delta_updatable?(nil, _target, _product, _fwup_version), do: false

  def delta_updatable?(source, target, product, fwup_version) do
    product.delta_updatable and
      target.delta_updatable and
      source.delta_updatable and
      Version.match?(fwup_version, @min_fwup_delta_updatable_version)
  end

  @doc """
  Returns true if Version.match? and all deployment tags are in device tags.
  """
  def matches_deployment?(
        %Device{tags: tags, firmware_metadata: %FirmwareMetadata{version: version}},
        %Deployment{conditions: %{"version" => requirement, "tags" => dep_tags}}
      ) do
    if version_match?(version, requirement) and tags_match?(tags, dep_tags) do
      true
    else
      false
    end
  end

  def matches_deployment?(_, _), do: false

  @spec update_deployment(Device.t(), Deployment.t()) :: Device.t()
  def update_deployment(device, deployment) do
    device =
      device
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:deployment_id, deployment.id)
      |> Repo.update!()

    _ = broadcast(device, "devices/deployment-updated", %{deployment_id: deployment.id})

    Map.put(device, :deployment, deployment)
  end

  @spec clear_deployment(Device.t()) :: Device.t()
  def clear_deployment(device) do
    device =
      device
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:deployment_id, nil)
      |> Repo.update!()

    _ = broadcast(device, "devices/deployment-cleared")

    Map.put(device, :deployment, nil)
  end

  @spec failure_threshold_met?(Device.t(), Deployment.t()) :: boolean()
  def failure_threshold_met?(%Device{} = device, %Deployment{} = deployment) do
    Enum.count(device.update_attempts) >= deployment.device_failure_threshold
  end

  @spec failure_rate_met?(Device.t(), Deployment.t()) :: boolean()
  def failure_rate_met?(%Device{} = device, %Deployment{} = deployment) do
    seconds_ago =
      Timex.shift(DateTime.utc_now(), seconds: -deployment.device_failure_rate_seconds)

    attempts =
      Enum.filter(device.update_attempts, fn attempt ->
        DateTime.compare(seconds_ago, attempt) == :lt
      end)

    Enum.count(attempts) >= deployment.device_failure_rate_amount
  end

  @doc """
  Devices that haven't been automatically blocked are not in the penalty window.
  Devices that have a time greater than now are in the penalty window.
  """
  def device_in_penalty_box?(device, now \\ DateTime.utc_now())

  def device_in_penalty_box?(%{updates_blocked_until: nil}, _now), do: false

  def device_in_penalty_box?(device, now) do
    DateTime.compare(device.updates_blocked_until, now) == :gt
  end

  defp updates_blocked?(device, now) do
    device.updates_enabled == false || device_in_penalty_box?(device, now)
  end

  def device_matches_deployment?(device, deployment) do
    device.firmware_metadata.uuid == deployment.firmware.uuid
  end

  def verify_update_eligibility(device, deployment, now \\ DateTime.utc_now()) do
    cond do
      not deployment.is_active ->
        {:error, :deployment_not_active, device}

      device_matches_deployment?(device, deployment) ->
        {:error, :up_to_date, device}

      updates_blocked?(device, now) ->
        clear_inflight_update(device)

        {:error, :updates_blocked, device}

      failure_rate_met?(device, deployment) ->
        blocked_until =
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.add(deployment.penalty_timeout_minutes * 60, :second)

        DeviceTemplates.audit_firmware_upgrade_blocked(deployment, device)
        clear_inflight_update(device)

        {:ok, device} = update_device(device, %{updates_blocked_until: blocked_until})

        {:error, :updates_blocked, device}

      failure_threshold_met?(device, deployment) ->
        blocked_until =
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.add(deployment.penalty_timeout_minutes * 60, :second)

        DeviceTemplates.audit_firmware_upgrade_blocked(deployment, device)
        clear_inflight_update(device)

        {:ok, device} = update_device(device, %{updates_blocked_until: blocked_until})

        {:error, :updates_blocked, device}

      true ->
        {:ok, device}
    end
  end

  def update_attempted(device, now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    changeset =
      device
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:update_attempts, [now | device.update_attempts])

    Multi.new()
    |> Multi.update(:device, changeset)
    |> Multi.run(:audit_device, fn _, _ ->
      DeviceTemplates.audit_update_attempt(device)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{device: device}} ->
        {:ok, device}

      err ->
        err
    end
  end

  def firmware_update_successful(device) do
    :telemetry.execute([:nerves_hub, :devices, :update, :successful], %{count: 1}, %{
      identifier: device.identifier,
      firmware_uuid: device.firmware_metadata.uuid
    })

    DeviceTemplates.audit_firmware_updated(device)

    # Clear the inflight update, no longer inflight!
    inflight_update =
      Repo.get_by(InflightUpdate,
        device_id: device.id,
        firmware_uuid: device.firmware_metadata.uuid
      )

    if inflight_update != nil do
      Orchestrator.device_updated(inflight_update.deployment_id)

      Deployment
      |> where([d], d.id == ^inflight_update.deployment_id)
      |> Repo.update_all(inc: [current_updated_devices: 1])

      Repo.delete(inflight_update)
    end

    device
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_change(:update_attempts, [])
    |> Ecto.Changeset.put_change(:updates_blocked_until, nil)
    |> Repo.update()
  end

  def up_to_date_count(%Deployment{} = deployment) do
    Device
    |> where([d], d.deployment_id == ^deployment.id)
    |> where([d], d.firmware_metadata["uuid"] == ^deployment.firmware.uuid)
    |> Repo.aggregate(:count)
  end

  @spec updating_count(Deployment.t()) :: term() | nil
  def updating_count(%Deployment{id: id}) do
    InflightUpdate
    |> where([ifu], ifu.deployment_id == ^id)
    |> Repo.aggregate(:count)
  end

  @spec waiting_for_update_count(Deployment.t()) :: term() | nil
  def waiting_for_update_count(%Deployment{} = deployment) do
    Device
    |> where([d], d.deployment_id == ^deployment.id)
    |> where(
      [d],
      is_nil(d.firmware_metadata) or d.firmware_metadata["uuid"] != ^deployment.firmware.uuid
    )
    |> Repo.aggregate(:count)
  end

  def restore_device(%Device{} = device) do
    update_device(device, %{deleted_at: nil})
  end

  @doc """
  Move a device to a different product

  If the new target product is in a different organization, this will
  attempt to also copy any signing keys the device might be expecting
  to the new organization. However, it is best effort only.

  Moving a device will also trigger a deployment check to see if there
  is an update available from the new product/org for the device. It is
  up to the user to ensure the new device is configured with any new/different
  signing keys from the new org before moving otherwise the device
  might fail to update because of an unknown key.
  """
  @spec move(Device.t() | [Device.t()], Product.t(), User.t()) :: Repo.transaction()
  def move(%Device{} = device, product, user) do
    product = Repo.preload(product, :org)

    attrs = %{
      org_id: product.org_id,
      product_id: product.id,
      deployment_id: nil
    }

    _ = maybe_copy_firmware_keys(device, product.org)

    description =
      "User #{user.name} moved device #{device.identifier} to #{product.org.name} : #{product.name}"

    source_product = %Product{
      id: device.product_id,
      org_id: device.org_id
    }

    Multi.new()
    |> Multi.run(:move, fn _, _ -> update_device(device, attrs) end)
    |> Multi.run(:audit_device, fn _, _ ->
      AuditLogs.audit(user, device, description)
    end)
    |> Multi.run(:audit_target, fn _, _ ->
      AuditLogs.audit(user, product, description)
    end)
    |> Multi.run(:audit_source, fn _, _ ->
      AuditLogs.audit(user, source_product, description)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{move: updated}} ->
        _ = broadcast(updated, "moved")
        {:ok, updated}

      err ->
        err
    end
  end

  @spec tag_device(Device.t() | [Device.t()], User.t(), list(String.t())) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def tag_device(%Device{} = device, user, tags) do
    description = "User #{user.name} updated device #{device.identifier} tags"
    params = %{tags: tags}
    update_device_with_audit(device, params, user, description)
  end

  @spec update_device_with_audit(Device.t(), map(), User.t(), String.t()) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def update_device_with_audit(device, params, user, description) do
    Multi.new()
    |> Multi.run(:update_with_audit, fn _, _ ->
      update_device(device, params, broadcast: false)
    end)
    |> Multi.run(:audit_device, fn _, _ ->
      AuditLogs.audit(user, device, description)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{update_with_audit: updated}} ->
        _ = broadcast(device, "devices/updated")
        {:ok, updated}

      err ->
        err
    end
  end

  @spec enable_updates(Device.t() | [Device.t()], User.t()) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def enable_updates(%Device{} = device, user) do
    description = "User #{user.name} enabled updates for device #{device.identifier}"
    params = %{updates_enabled: true, update_attempts: []}
    update_device_with_audit(device, params, user, description)
  end

  @spec disable_updates(Device.t() | [Device.t()], User.t()) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def disable_updates(%Device{} = device, user) do
    description = "User #{user.name} disabled updates for device #{device.identifier}"
    params = %{updates_enabled: false}
    update_device_with_audit(device, params, user, description)
  end

  def toggle_health(device, user) do
    case device.updates_enabled do
      true ->
        disable_updates(device, user)

      false ->
        enable_updates(device, user)
    end
  end

  def clear_penalty_box(%Device{} = device, user) do
    description = "User #{user.name} removed device #{device.identifier} from the penalty box"
    params = %{updates_blocked_until: nil, update_attempts: []}
    update_device_with_audit(device, params, user, description)
  end

  @spec move_many_to_deployment([integer()], integer()) ::
          {:ok, %{updated: non_neg_integer(), ignored: non_neg_integer()}}
  def move_many_to_deployment(device_ids, deployment_id) do
    %{firmware: firmware} =
      Deployment |> where(id: ^deployment_id) |> preload(:firmware) |> Repo.one()

    {devices_updated_count, _} =
      Device
      |> where([d], d.id in ^device_ids)
      |> where([d], d.firmware_metadata["platform"] == ^firmware.platform)
      |> where([d], d.firmware_metadata["architecture"] == ^firmware.architecture)
      |> Repo.update_all(set: [deployment_id: deployment_id])

    :ok = Enum.each(device_ids, &broadcast(%Device{id: &1}, "devices/updated"))

    {:ok, %{updated: devices_updated_count, ignored: length(device_ids) - devices_updated_count}}
  end

  @spec move_many([Device.t()], Product.t(), User.t()) :: %{
          ok: [Device.t()],
          error: [{Ecto.Multi.name(), any()}]
        }
  def move_many(devices, product, user) do
    product = Repo.preload(product, :org)

    Enum.map(devices, &Task.Supervisor.async(Tasks, __MODULE__, :move, [&1, product, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  @spec disable_updates([Device.t()], User.t()) :: %{
          ok: [Device.t()],
          error: [{Ecto.Multi.name(), any()}]
        }
  def disable_updates_for_devices(devices, user) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, __MODULE__, :disable_updates, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  @spec tag_devices([Device.t()], User.t(), list(String.t())) :: %{
          ok: [Device.t()],
          error: [{Ecto.Multi.name(), any()}]
        }
  def tag_devices(devices, user, tags) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, __MODULE__, :tag_device, [&1, user, tags]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  @spec enable_updates_for_devices([Device.t()], User.t()) :: %{
          ok: [Device.t()],
          error: [{Ecto.Multi.name(), any()}]
        }
  def enable_updates_for_devices(devices, user) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, __MODULE__, :enable_updates, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def clear_penalty_box_for_devices(devices, user) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, __MODULE__, :clear_penalty_box, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  @spec get_devices_by_id([non_neg_integer()]) :: [Device.t()]
  def get_devices_by_id(ids) when is_list(ids) do
    from(d in Device, where: d.id in ^ids)
    |> Repo.all()
  end

  defp maybe_broadcast(device, event, opts) do
    if Keyword.get(opts, :broadcast, true) do
      broadcast(device, event)
    else
      :ok
    end
  end

  defp broadcast(device, event), do: broadcast(device, event, %{})

  defp broadcast(%Device{id: id}, event, payload) do
    Phoenix.PubSub.broadcast(
      NervesHub.PubSub,
      "device:#{id}",
      %Phoenix.Socket.Broadcast{event: event, payload: payload}
    )
  end

  def save_device_health(device_status) do
    Multi.new()
    |> Multi.insert(:insert_health, DeviceHealth.save(device_status))
    |> Ecto.Multi.update_all(:update_device, &update_health_on_device/1, [])
    |> Repo.transaction()
    |> case do
      {:ok, %{insert_health: health}} ->
        {:ok, health}

      {:error, _, changeset, _} ->
        {:error, changeset}
    end
  end

  defp update_health_on_device(%{insert_health: health}) do
    Device
    |> where(id: ^health.device_id)
    |> update(set: [latest_health_id: ^health.id])
  end

  def truncate_device_health() do
    interval =
      Application.get_env(:nerves_hub, :device_health_days_to_retain)

    delete_limit = Application.get_env(:nerves_hub, :device_health_delete_limit)
    time_ago = DateTime.shift(DateTime.utc_now(), day: -interval)

    query =
      DeviceHealth
      |> join(:inner, [dh], d in Device, on: dh.device_id == d.id)
      |> where([dh, _d], dh.inserted_at < ^time_ago)
      |> where([dh, d], dh.id != d.latest_health_id)
      |> select([dh], dh.id)
      |> limit(^delete_limit)

    {delete_count, _} =
      DeviceHealth
      |> where([dh], dh.id in subquery(query))
      |> Repo.delete_all(timeout: 30_000)

    if delete_count == 0 do
      :ok
    else
      # relax stress on Ecto pool and go again
      Process.sleep(2000)
      truncate_device_health()
    end
  end

  def get_latest_health(device_id) do
    DeviceHealth
    |> where(device_id: ^device_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.all()
    |> case do
      [] -> nil
      [latest] -> latest
    end
  end

  def get_device_health(device_id) do
    DeviceHealth
    |> where(device_id: ^device_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_device_health(device_id, unit, amount) do
    DeviceHealth
    |> where(device_id: ^device_id)
    |> where([d], d.inserted_at > ago(^amount, ^unit))
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  defp version_match?(_vsn, ""), do: true

  defp version_match?(version, requirement) do
    Version.match?(version, requirement)
  end

  defp tags_match?(nil, deployment_tags), do: tags_match?([], deployment_tags)
  defp tags_match?(device_tags, nil), do: tags_match?(device_tags, [])

  defp tags_match?(device_tags, deployment_tags) do
    Enum.all?(deployment_tags, fn tag -> tag in device_tags end)
  end

  def maybe_copy_firmware_keys(%{firmware_metadata: %{uuid: uuid}, org_id: source}, %Org{
        id: target
      }) do
    existing_target_keys = from(k in OrgKey, where: [org_id: ^target], select: k.key)

    from(
      k in OrgKey,
      join: f in Firmware,
      on: [org_key_id: k.id],
      where: f.uuid == ^uuid and k.org_id == ^source,
      where: k.key not in subquery(existing_target_keys),
      select: %{name: k.name, key: k.key, org_id: type(^target, :integer)}
    )
    |> Repo.one()
    |> case do
      %{} = attrs -> Accounts.create_org_key(attrs)
      _ -> :ignore
    end
  end

  def maybe_copy_firmware_keys(_old, _updated), do: :ignore

  @doc """
  Get distinct device platforms based on the product
  """
  def platforms(product_id) do
    Device
    |> select([d], fragment("?->>'platform'", d.firmware_metadata))
    |> distinct(true)
    |> where([d], d.product_id == ^product_id)
    |> order_by([d], fragment("?->>'platform'", d.firmware_metadata))
    |> Repo.all()
  end

  @doc """
  Deployment orchestrator told a device to update
  """
  def told_to_update(device, deployment) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(60 * deployment.inflight_update_expiration_minutes, :second)
      |> DateTime.truncate(:second)

    %{
      device_id: device.id,
      deployment_id: deployment.id,
      firmware_id: deployment.firmware_id,
      firmware_uuid: deployment.firmware.uuid,
      expires_at: expires_at
    }
    |> InflightUpdate.create_changeset()
    |> Repo.insert()
    |> case do
      {:ok, inflight_update} ->
        {:ok, inflight_update}

      {:error, _changeset} ->
        # Device already has an inflight update, fetch it
        case Repo.get_by(InflightUpdate, device_id: device.id, deployment_id: deployment.id) do
          nil ->
            :error

          inflight_update ->
            {:ok, inflight_update}
        end
    end
  end

  def clear_inflight_update(device) do
    InflightUpdate
    |> where([iu], iu.device_id == ^device.id)
    |> Repo.delete_all()
  end

  def delete_expired_inflight_updates() do
    InflightUpdate
    |> where([iu], iu.expires_at < fragment("now()"))
    |> Repo.delete_all()
  end

  def update_started!(inflight_update) do
    inflight_update
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_change(:status, "updating")
    |> Repo.update!()
  end

  def inflight_updates_for(%Deployment{} = deployment) do
    InflightUpdate
    |> where([iu], iu.deployment_id == ^deployment.id)
    |> preload([:device])
    |> Repo.all()
  end

  def count_inflight_updates_for(%Deployment{} = deployment) do
    InflightUpdate
    |> select([iu], count(iu))
    |> where([iu], iu.deployment_id == ^deployment.id)
    |> Repo.one()
  end

  def enable_extension_setting(%Device{} = device, extension_string) do
    device = get_device(device.id)

    Device.changeset(device, %{"extensions" => %{extension_string => true}})
    |> Repo.update()
    |> tap(fn
      {:ok, _} ->
        Extensions.broadcast_extension_event(device, "attach", extension_string)

      _ ->
        :nope
    end)
  end

  def disable_extension_setting(%Device{} = device, extension_string) do
    device = get_device(device.id)

    Device.changeset(device, %{"extensions" => %{extension_string => false}})
    |> Repo.update()
    |> tap(fn
      {:ok, _} ->
        Extensions.broadcast_extension_event(device, "detach", extension_string)

      _ ->
        :nope
    end)
  end

  def preload_product(%Device{} = device) do
    device
    |> Repo.preload(:product)
  end
end
