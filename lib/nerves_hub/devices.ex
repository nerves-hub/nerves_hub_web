defmodule NervesHub.Devices do
  import Ecto.Query

  require Logger

  alias Ecto.Changeset
  alias Ecto.Multi
  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Certificate
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceFiltering
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.PinnedDevice
  alias NervesHub.Devices.SharedSecretAuth
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Devices.UpdateStats
  alias NervesHub.Extensions
  alias NervesHub.Filtering, as: CommonFiltering
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.TaskSupervisor, as: Tasks

  def get_device(device_id) when is_integer(device_id) do
    Repo.get(Device, device_id)
  end

  def get_complete_device(device_id) do
    Device
    |> where([d], d.id == ^device_id)
    |> join(:left, [d], o in assoc(d, :org))
    |> join(:left, [d, o], p in assoc(d, :product))
    |> join(:left, [d, o, p], dg in assoc(d, :deployment_group))
    |> join(:left, [d, o, p, dg], f in assoc(dg, :firmware))
    |> join(:left, [d, o, p, dg, f], lc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:left, [d, o, p, dg, f, lc], lh in assoc(d, :latest_health), as: :latest_health)
    |> preload([d, o, p, dg, f, latest_connection: lc, latest_health: lh],
      org: o,
      product: p,
      deployment_group: {dg, firmware: f},
      latest_connection: lc,
      latest_health: lh
    )
    |> Repo.exclude_deleted()
    |> Repo.one()
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
    |> join(:left, [d, o, p], dg in assoc(d, :deployment_group))
    |> join(:left, [d, o, p, dg], f in assoc(dg, :firmware))
    |> join(:left, [d, o, p, dg, f], lc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:left, [d, o, p, dg, f, lc], lh in assoc(d, :latest_health), as: :latest_health)
    |> Repo.exclude_deleted()
    |> DeviceFiltering.sort(sorting)
    |> DeviceFiltering.build_filters(filters)
    |> preload([d, o, p, dg, f, latest_connection: lc, latest_health: lh],
      org: o,
      product: p,
      deployment_group: {dg, firmware: f},
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

  @spec filter(Product.t(), User.t(), map()) :: {[Device.t()], Flop.Meta.t()}
  def filter(product, user, opts) do
    base_query =
      Device
      |> join(:left, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
      |> join(:left, [d, dc], dh in assoc(d, :latest_health), as: :latest_health)
      |> join(:left, [d, dc, dh], pd in PinnedDevice,
        on: pd.device_id == d.id and pd.user_id == ^user.id,
        as: :pinned
      )
      |> preload([latest_connection: lc], latest_connection: lc)
      |> preload([latest_health: lh], latest_health: lh)

    CommonFiltering.filter(
      base_query,
      product,
      opts
    )
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
        {:ok, Repo.preload(device, [:org, :product, :latest_connection, deployment_group: [:firmware]])}
    end
  end

  def get_by_identifier!(identifier) do
    device = Repo.get_by!(Device, identifier: identifier)
    Repo.preload(device, [:org, :product, :latest_connection, deployment_group: [:firmware]])
  end

  @spec get_device_by_identifier(Org.t(), String.t()) :: {:ok, Device.t()} | {:error, :not_found}
  def get_device_by_identifier(org, identifier, preload_assoc \\ nil) when is_binary(identifier) do
    get_device_by_identifier_query(org, identifier, preload_assoc)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  @spec get_device_by_identifier!(Org.t(), String.t()) :: Device.t()
  def get_device_by_identifier!(org, identifier, preload_assoc \\ nil) when is_binary(identifier) do
    get_device_by_identifier_query(org, identifier, preload_assoc)
    |> Repo.one!()
  end

  defp get_device_by_identifier_query(%Org{id: org_id}, identifier, preload_assoc) do
    Device
    |> where(identifier: ^identifier)
    |> where(org_id: ^org_id)
    |> join(:left, [d], o in assoc(d, :org))
    |> join(:left, [d], dp in assoc(d, :deployment_group), as: :deployment_group)
    |> preload([d, o, deployment_group: dg], org: o, deployment_group: dg)
    |> join_and_preload(preload_assoc)
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

  defp join_and_preload(query, :product) do
    query
    |> join(:left, [d], p in assoc(d, :product), as: :product)
    |> preload([product: p], product: p)
  end

  defp join_and_preload(query, :firmware) do
    query
    |> join(:left, [d, deployment_group: dg], f in assoc(dg, :firmware), as: :firmware)
    |> preload([deployment_group: dg, firmware: f], deployment_group: {dg, firmware: f})
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
          {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
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
    end
  end

  def get_device_by(filters) do
    Repo.get_by(Device, filters)
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

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
    pinned_devices_query = from(p in PinnedDevice, where: p.device_id == ^device.id)
    changeset = Repo.soft_delete_changeset(device)

    Multi.new()
    |> Multi.delete_all(:device_certificates, device_certificates_query)
    |> Multi.delete_all(:pinned_devices, pinned_devices_query)
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

  def get_device_by_certificate(%DeviceCertificate{device: %Device{} = device}), do: {:ok, Repo.preload(device, :org)}

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

  @spec get_device_firmware_for_delta_generation_by_deployment_group(binary()) ::
          list({source_firmware_id(), target_firmware_id()})
  def get_device_firmware_for_delta_generation_by_deployment_group(deployment_id) do
    DeploymentGroup
    |> where([dep], dep.id == ^deployment_id)
    |> join(:inner, [dep], dev in Device, on: dev.deployment_id == dep.id)
    |> join(:inner, [dep, dev], f in Firmware, on: f.uuid == fragment("d1.firmware_metadata->>'uuid'"))
    # Exclude the current firmware, we don't need to generate that one
    |> where([dep, dev, f], f.id != dep.firmware_id)
    |> select([dep, dev, f], {f.id, dep.firmware_id})
    |> distinct(true)
    |> Repo.all()
  end

  @spec update_firmware_metadata(
          Device.t(),
          FirmwareMetadata.t() | nil,
          Device.firmware_validation_statuses(),
          boolean()
        ) ::
          {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update_firmware_metadata(device, nil, validation_status, auto_revert_detected?) do
    update_device(device, %{
      firmware_validation_status: validation_status,
      firmware_auto_revert_detected: auto_revert_detected?
    })
  end

  def update_firmware_metadata(device, metadata, validation_status, auto_revert_detected?) do
    DeviceTemplates.audit_firmware_metadata_updated(device)

    update_device(device, %{
      firmware_metadata: metadata,
      firmware_validation_status: validation_status,
      firmware_auto_revert_detected: auto_revert_detected?
    })
  end

  def firmware_validated(device) do
    DeviceTemplates.audit_firmware_validated(device)

    {:ok, device} = update_device(device, %{firmware_validation_status: "validated"})

    Phoenix.Channel.Server.broadcast_from!(
      NervesHub.PubSub,
      self(),
      "device:#{device.identifier}:internal",
      "firmware:validated",
      %{}
    )

    {:ok, device}
  end

  @spec update_device(Device.t(), map(), broadcast: boolean()) ::
          {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update_device(%Device{} = device, params, opts \\ []) do
    changeset = Device.changeset(device, params)

    case Repo.update(changeset) do
      {:ok, device} ->
        _ = maybe_broadcast_updated(device, opts)

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

  If the deployment group has `enable_priority_updates` set to false (the default),
  devices are ordered by their `latest_connection`: devices connected the longest will
  be updated first.

  If the deployment group has `enable_priority_updates` set to true,
  devices are ordered by most recently connected for the first time (`device.first_seen_at`)
  """
  @spec available_for_update(DeploymentGroup.t(), non_neg_integer()) :: [Device.t()]
  def available_for_update(deployment_group, count) do
    build_available_devices_query(deployment_group, count, [])
    |> Repo.all()
  end

  @doc """
  Get devices eligible for priority queue updates.

  Similar to `available_for_update/2` but filters devices whose firmware version
  is less than or equal to the priority_queue_firmware_version_threshold.
  """
  @spec available_for_priority_update(DeploymentGroup.t(), non_neg_integer()) :: [Device.t()]

  # No threshold set, return empty list
  def available_for_priority_update(%DeploymentGroup{priority_queue_firmware_version_threshold: threshold}, _count)
      when is_nil(threshold),
      do: []

  def available_for_priority_update(deployment_group, count) do
    threshold = deployment_group.priority_queue_firmware_version_threshold

    build_available_devices_query(deployment_group, count, version_threshold: threshold)
    |> Repo.all()
  end

  # Builds the query for finding available devices for updates
  # Options:
  #   - :version_threshold - Optional firmware version threshold for priority queue filtering
  defp build_available_devices_query(deployment_group, count, opts) do
    now = DateTime.utc_now(:second)
    version_threshold = Keyword.get(opts, :version_threshold)

    Device
    |> join(:inner, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:inner, [d], dg in assoc(d, :deployment_group), as: :deployment_group)
    |> join(:inner, [deployment_group: dg], f in assoc(dg, :firmware),
      on: [product_id: ^deployment_group.product_id],
      as: :firmware
    )
    |> join(:left, [d], ifu in InflightUpdate, on: d.id == ifu.device_id, as: :inflight_update)
    |> where(deployment_id: ^deployment_group.id)
    |> where(updates_enabled: true)
    |> where([d], d.firmware_validation_status in [:validated, :unknown])
    |> where([latest_connection: lc], lc.status == :connected)
    |> where([d], not is_nil(d.firmware_metadata))
    |> where([d, firmware: f], fragment("(? #>> '{\"uuid\"}') != ?", d.firmware_metadata, f.uuid))
    |> where([inflight_update: ifu], is_nil(ifu))
    |> where([d], is_nil(d.updates_blocked_until) or d.updates_blocked_until < ^now)
    |> then(fn query ->
      if version_threshold do
        where(
          query,
          [d],
          fragment("semver_match(? #>> '{\"version\"}', ?)", d.firmware_metadata, ^"<= #{version_threshold}")
        )
      else
        query
      end
    end)
    |> then(fn query ->
      case deployment_group.queue_management do
        :FIFO ->
          order_by(query, [latest_connection: lc], asc: lc.established_at)

        :LIFO ->
          order_by(query, [d], desc_nulls_last: d.first_seen_at)
      end
    end)
    |> limit(^count)
  end

  @doc """
  Resolve an update for the device's deployment
  """
  @spec resolve_update(Device.t()) :: UpdatePayload.t()
  def resolve_update(%Device{status: :registered}), do: %UpdatePayload{update_available: false}

  def resolve_update(%Device{deployment_id: nil}), do: %UpdatePayload{update_available: false}

  def resolve_update(%Device{firmware_metadata: fw_meta} = device) do
    Logger.metadata(device_id: device.id, source_firmware_uuid: Map.get(fw_meta, :uuid))
    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(device)

    opts =
      if proxy_url = get_in(deployment_group.org.settings.firmware_proxy_url) do
        [firmware_proxy_url: proxy_url]
      else
        []
      end

    do_resolve_update(device, deployment_group, opts)
  end

  defp do_resolve_update(device, deployment_group, opts) do
    case verify_update_eligibility(device, deployment_group) do
      {:ok, _device} ->
        case get_delta_or_firmware_url(device, deployment_group) do
          {:ok, url} ->
            {:ok, meta} = Firmwares.metadata_from_firmware(deployment_group.firmware)

            firmware_url =
              if opts[:firmware_proxy_url] do
                opts[:firmware_proxy_url] <> "?firmware=#{Base.url_encode64(url, padding: false)}"
              else
                url
              end

            %UpdatePayload{
              update_available: true,
              firmware_url: firmware_url,
              firmware_meta: meta,
              deployment_group: deployment_group,
              deployment_id: deployment_group.id
            }

          {:error, reason} ->
            Logger.info(
              "Firmware URL could not be generated",
              reason: reason,
              source_firmware: Map.get(device.firmware_metadata, :uuid),
              target_firmware: deployment_group.firmware.uuid
            )

            %UpdatePayload{update_available: false}
        end

      {:error, :deployment_group_not_active, _device} ->
        %UpdatePayload{update_available: false}

      {:error, :up_to_date, _device} ->
        %UpdatePayload{update_available: false}

      {:error, :updates_blocked, _device} ->
        %UpdatePayload{update_available: false}
    end
  end

  @doc """
  Returns true if the device is delta updatable.

  Checks update tool version information and similar metadata to determine if
  the device is delta updatable.
  """
  @spec delta_updatable?(Device.t(), DeploymentGroup.t() | Firmware.t()) :: boolean()
  def delta_updatable?(device, %DeploymentGroup{} = deployment_group) do
    Logger.metadata(device_id: device.id, deployment_group_id: deployment_group.id)
    # note that source delta does not need delta markers to be updatable
    # Any advanced decision about whether to delta update or not are delegated
    # to the specialized update tool implementation

    deployment_group.delta_updatable and
      not is_nil(deployment_group.firmware) and
      delta_updatable?(device, deployment_group.firmware)
  end

  def delta_updatable?(%{firmware_metadata: fw_meta} = device, %Firmware{} = firmware) do
    Logger.metadata(
      device_id: device.id,
      target_firmware_uuid: firmware.uuid,
      source_firmware_uuid: Map.get(fw_meta, :uuid)
    )

    firmware.delta_updatable and
      :delta == update_tool().device_update_type(device, firmware)
  end

  @spec delta_ready?(Device.t(), Firmware.t()) :: boolean()
  def delta_ready?(%Device{firmware_metadata: %{uuid: source_uuid}}, %Firmware{id: target_id, product_id: product_id}) do
    source_firmware_id_query =
      Firmware
      |> where(uuid: ^source_uuid)
      |> where(product_id: ^product_id)
      |> select([f], f.id)

    query =
      FirmwareDelta
      |> where([fd], fd.source_id == subquery(source_firmware_id_query))
      |> where([fd], fd.target_id == ^target_id)
      |> where([fd], fd.status == :completed)

    Repo.exists?(query)
  end

  @doc """
  Returns true if Version.match? and all deployment tags are in device tags.
  """
  def matches_deployment_group?(
        %Device{tags: tags, firmware_metadata: %FirmwareMetadata{version: version}},
        %DeploymentGroup{conditions: %{version: requirement, tags: dep_tags}}
      ) do
    if version_match?(version, requirement) and tags_match?(tags, dep_tags) do
      true
    else
      false
    end
  end

  def matches_deployment_group?(_, _), do: false

  @spec update_deployment_group(Device.t(), DeploymentGroup.t()) :: Device.t()
  def update_deployment_group(device, deployment_group) do
    device =
      device
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:deployment_id, deployment_group.id)
      |> Repo.update!()

    DeviceEvents.deployment_assigned(device)

    deployment_group = Repo.preload(deployment_group, :firmware)
    Map.put(device, :deployment_group, deployment_group)
  end

  @spec clear_deployment_group(Device.t()) :: Device.t()
  def clear_deployment_group(device) do
    device =
      device
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:deployment_id, nil)
      |> Repo.update!()

    DeviceEvents.deployment_cleared(device)

    Map.put(device, :deployment_group, nil)
  end

  @spec failure_threshold_met?(Device.t(), DeploymentGroup.t()) :: boolean()
  def failure_threshold_met?(%Device{} = device, %DeploymentGroup{} = deployment_group) do
    Enum.count(device.update_attempts) >= deployment_group.device_failure_threshold
  end

  @spec failure_rate_met?(Device.t(), DeploymentGroup.t()) :: boolean()
  def failure_rate_met?(%Device{} = device, %DeploymentGroup{} = deployment_group) do
    seconds_ago =
      Timex.shift(DateTime.utc_now(), seconds: -deployment_group.device_failure_rate_seconds)

    attempts =
      Enum.filter(device.update_attempts, fn attempt ->
        DateTime.before?(seconds_ago, attempt)
      end)

    Enum.count(attempts) >= deployment_group.device_failure_rate_amount
  end

  @doc """
  Devices that haven't been automatically blocked are not in the penalty window.
  Devices that have a time greater than now are in the penalty window.
  """
  def device_in_penalty_box?(device, now \\ DateTime.utc_now())

  def device_in_penalty_box?(%{updates_blocked_until: nil}, _now), do: false

  def device_in_penalty_box?(device, now) do
    DateTime.after?(device.updates_blocked_until, now)
  end

  defp updates_blocked?(device, now) do
    device.updates_enabled == false || device_in_penalty_box?(device, now)
  end

  def device_matches_deployment_group?(device, deployment_group) do
    device.firmware_metadata.uuid == deployment_group.firmware.uuid
  end

  def verify_update_eligibility(device, deployment_group, now \\ DateTime.utc_now()) do
    cond do
      not deployment_group.is_active ->
        {:error, :deployment_group_not_active, device}

      device_matches_deployment_group?(device, deployment_group) ->
        {:error, :up_to_date, device}

      updates_blocked?(device, now) ->
        clear_inflight_update(device)

        {:error, :updates_blocked, device}

      failure_rate_met?(device, deployment_group) ->
        {:ok, device} = put_device_in_penalty_box(device, deployment_group)

        {:error, :updates_blocked, device}

      failure_threshold_met?(device, deployment_group) ->
        {:ok, device} = put_device_in_penalty_box(device, deployment_group)

        {:error, :updates_blocked, device}

      true ->
        {:ok, device}
    end
  end

  defp put_device_in_penalty_box(device, deployment_group) do
    blocked_until =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(deployment_group.penalty_timeout_minutes * 60, :second)

    :ok = DeviceTemplates.audit_firmware_upgrade_blocked(deployment_group, device)
    _ = clear_inflight_update(device)

    Logger.info("Device #{device.identifier} put in penalty box until #{blocked_until}")

    update_device(device, %{updates_blocked_until: blocked_until, update_attempts: []})
  end

  @spec update_attempted(Device.t(), DateTime.t()) :: :ok | {:error, Changeset.t()}
  def update_attempted(device, now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    Multi.new()
    |> Multi.update_all(
      :device,
      fn _ ->
        Device
        |> where(id: ^device.id)
        |> update(set: [update_attempts: fragment("update_attempts || ?::timestamp", ^now)])
      end,
      []
    )
    |> Multi.run(:audit_device, fn _, _ ->
      DeviceTemplates.audit_update_attempt(device)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        :ok

      err ->
        err
    end
  end

  @spec firmware_update_successful(Device.t(), FirmwareMetadata.t() | nil) ::
          {:ok, Device.t()} | {:error, Changeset.t()}
  def firmware_update_successful(device, previous_metadata) do
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

    _ =
      if inflight_update do
        DeploymentGroup
        |> where([d], d.id == ^inflight_update.deployment_id)
        |> Repo.update_all(inc: [current_updated_devices: 1])

        Repo.delete(inflight_update)

        # let the orchestrator know that an inflight update completed
        deployment_device_updated(device)
      end

    _ = UpdateStats.log_update(device, previous_metadata)

    device
    |> Device.clear_updates_information_changeset()
    |> Repo.update()
  end

  def deployment_device_online(%Device{deployment_id: nil}) do
    :ok
  end

  def deployment_device_online(device) do
    firmware_uuid = if(device.firmware_metadata, do: device.firmware_metadata.uuid)

    payload = %{
      updates_enabled: device.updates_enabled,
      updates_blocked_until: device.updates_blocked_until,
      firmware_uuid: firmware_uuid
    }

    _ =
      Phoenix.Channel.Server.broadcast(
        NervesHub.PubSub,
        "orchestrator:deployment:#{device.deployment_id}",
        "device-online",
        payload
      )

    :ok
  end

  def deployment_device_updated(%Device{deployment_id: nil}) do
    :ok
  end

  def deployment_device_updated(device) do
    _ =
      Phoenix.Channel.Server.broadcast(
        NervesHub.PubSub,
        "orchestrator:deployment:#{device.deployment_id}",
        "device-updated",
        %{}
      )

    :ok
  end

  def up_to_date_count(%DeploymentGroup{} = deployment_group) do
    Device
    |> where([d], d.deployment_id == ^deployment_group.id)
    |> where([d], d.firmware_metadata["uuid"] == ^deployment_group.firmware.uuid)
    |> Repo.aggregate(:count)
  end

  @spec updating_count(DeploymentGroup.t()) :: term() | nil
  def updating_count(%DeploymentGroup{id: id}) do
    InflightUpdate
    |> where([ifu], ifu.deployment_id == ^id)
    |> Repo.aggregate(:count)
  end

  @spec waiting_for_update_count(DeploymentGroup.t()) :: term() | nil
  def waiting_for_update_count(%DeploymentGroup{} = deployment_group) do
    Device
    |> where([d], d.deployment_id == ^deployment_group.id)
    |> where(
      [d],
      is_nil(d.firmware_metadata) or
        d.firmware_metadata["uuid"] != ^deployment_group.firmware.uuid
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
    |> Multi.delete_all(:pinned_devices, &unpin_unauthorized_users_query/1)
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
      {:ok, %{move: device}} ->
        DeviceEvents.moved_product(device)
        {:ok, device}

      err ->
        err
    end
  end

  # Queries pinned devices where user is unauthorized to device's org.
  defp unpin_unauthorized_users_query(%{move: device}) do
    users_in_org =
      OrgUser
      |> where(org_id: ^device.org_id)
      |> select([:user_id])

    PinnedDevice
    |> where([p], p.device_id == ^device.id)
    |> where([p], p.user_id not in subquery(users_in_org))
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
        DeviceEvents.updated(device)
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

    case update_device_with_audit(device, params, user, description) do
      {:ok, device} = result ->
        _ =
          if device.deployment_id do
            Phoenix.Channel.Server.broadcast(
              NervesHub.PubSub,
              "orchestrator:deployment:#{device.deployment_id}",
              "device-updated",
              %{}
            )
          end

        result

      {:error, _, _, _} = result ->
        result
    end
  end

  @spec disable_updates(Device.t() | [Device.t()], User.t()) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def disable_updates(%Device{} = device, user) do
    description = "User #{user.name} disabled updates for device #{device.identifier}"
    params = %{updates_enabled: false}
    update_device_with_audit(device, params, user, description)
  end

  def toggle_automatic_updates(device, user) do
    case device.updates_enabled do
      true ->
        disable_updates(device, user)

      false ->
        enable_updates(device, user)
    end
  end

  def clear_penalty_box(%Device{} = device, user) do
    description = "User #{user.name} removed device #{device.identifier} from the penalty box"
    params = %{updates_blocked_until: nil, update_attempts: [], updates_enabled: true}
    update_device_with_audit(device, params, user, description)
  end

  def update_blocked_until(device, deployment) do
    blocked_until =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(deployment.penalty_timeout_minutes * 60, :second)

    DeviceTemplates.audit_firmware_upgrade_blocked(deployment, device)

    update_device(device, %{updates_blocked_until: blocked_until})
  end

  @doc """
  Move devices to a deployment group. A deployment group struct or id can
  be given. Devices are fetched by their id and also filtered by the given
  deployment group firmware's architecture and platform.

  `Repo.update_all()` is used to update the rows. The return informs how
  many rows were updated and how many were ignored because of a problem.

  move_many_to_deployment_group([1, 2, 3], deployment_group)
  > {:ok, %{updated: 3, ignored: 0}}
  """
  @spec move_many_to_deployment_group(
          [non_neg_integer()],
          DeploymentGroup.t() | non_neg_integer()
        ) ::
          {:ok, %{updated: non_neg_integer(), ignored: non_neg_integer()}}
  def move_many_to_deployment_group(device_ids, deployment_id) when is_number(deployment_id) do
    deployment_group =
      DeploymentGroup |> where(id: ^deployment_id) |> preload(:firmware) |> Repo.one()

    move_many_to_deployment_group(device_ids, deployment_group)
  end

  def move_many_to_deployment_group(device_ids, %DeploymentGroup{id: id} = deployment_group) do
    %{firmware: firmware} = Repo.preload(deployment_group, :firmware)

    {devices_updated_count, _} =
      Device
      |> Repo.exclude_deleted()
      |> where([d], d.id in ^device_ids)
      |> where([d], d.firmware_metadata["platform"] == ^firmware.platform)
      |> where([d], d.firmware_metadata["architecture"] == ^firmware.architecture)
      |> Repo.update_all([set: [deployment_id: id]], timeout: to_timeout(minute: 2))

    :ok = Enum.each(device_ids, &DeviceEvents.updated(%Device{id: &1}))

    {:ok, %{updated: devices_updated_count, ignored: length(device_ids) - devices_updated_count}}
  end

  @doc """
  Removes unmatched devices from deployment group. The given device ids are
  assumed to be ids of devices that "match" a deployment group's conditions,
  e.g. devices from ManagedDeployments.matched_device_ids/2. Devices are
  fetched by their id and also filtered by the deployment group's id and
  product id.

  `Repo.update_all()` is used to update the rows. The return informs how
  many rows were updated and how many were ignored because of a problem.

  remove_unmatched_devices_from_deployment_group([1, 2, 3], deployment_group)
  > {:ok, %{updated: 3, ignored: 0}}
  """
  @spec remove_unmatched_devices_from_deployment_group([non_neg_integer()], DeploymentGroup.t()) ::
          {:ok, %{updated: non_neg_integer(), ignored: non_neg_integer()}}
  def remove_unmatched_devices_from_deployment_group(matched_device_ids, deployment_group) do
    {devices_updated_count, _} =
      Device
      |> Repo.exclude_deleted()
      |> where([d], d.deployment_id == ^deployment_group.id)
      |> where([d], d.product_id == ^deployment_group.product_id)
      |> where([d], d.id not in ^matched_device_ids)
      |> Repo.update_all([set: [deployment_id: nil]], timeout: to_timeout(minute: 2))

    :ok = Enum.each(matched_device_ids, &DeviceEvents.updated(%Device{id: &1}))

    {:ok,
     %{
       updated: devices_updated_count,
       ignored: length(matched_device_ids) - devices_updated_count
     }}
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

  defp maybe_broadcast_updated(device, opts) do
    if Keyword.get(opts, :broadcast, true) do
      DeviceEvents.updated(device)
    else
      :ok
    end
  end

  @spec save_device_health(health_report :: map()) ::
          {:ok, DeviceHealth.t()} | {:error, Ecto.Changeset.t()}
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

  defp tags_match?(nil, deployment_group_tags), do: tags_match?([], deployment_group_tags)
  defp tags_match?(device_tags, nil), do: tags_match?(device_tags, [])

  defp tags_match?(device_tags, deployment_group_tags) do
    Enum.all?(deployment_group_tags, fn tag -> tag in device_tags end)
  end

  def maybe_copy_firmware_keys(%{firmware_metadata: %{uuid: uuid}, org_id: source}, %Org{id: target}) do
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
  @spec told_to_update(
          device_or_id :: Device.t() | integer(),
          deployment_group :: DeploymentGroup.t()
        ) ::
          {:ok, InflightUpdate.t()} | :error
  def told_to_update(device_or_id, deployment_group, opts \\ [])

  def told_to_update(%Device{id: id}, deployment_group, opts) do
    told_to_update(id, deployment_group, opts)
  end

  def told_to_update(device_id, deployment_group, opts) do
    deployment_group = Repo.preload(deployment_group, :firmware)

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(60 * deployment_group.inflight_update_expiration_minutes, :second)
      |> DateTime.truncate(:second)

    priority_queue = Keyword.get(opts, :priority_queue, false)

    %{
      device_id: device_id,
      deployment_id: deployment_group.id,
      firmware_id: deployment_group.firmware_id,
      firmware_uuid: deployment_group.firmware.uuid,
      expires_at: expires_at,
      priority_queue: priority_queue
    }
    |> InflightUpdate.create_changeset()
    |> Repo.insert()
    |> case do
      {:ok, inflight_update} ->
        broadcast_update_request(device_id, inflight_update, deployment_group)
        {:ok, inflight_update}

      {:error, _changeset} ->
        # TODO this logic doesn't feel right. We should revise this approach.
        # Device already has an inflight update, fetch it
        case Repo.get_by(InflightUpdate, device_id: device_id, deployment_id: deployment_group.id) do
          nil ->
            Logger.error("An inflight update could not be created or found for the device (#{device_id})")
            :error

          inflight_update ->
            broadcast_update_request(device_id, inflight_update, deployment_group)
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

  def update_started!(inflight_update, device, deployment) do
    Repo.transaction(fn ->
      DeviceTemplates.audit_device_deployment_group_update_triggered(
        device,
        deployment
      )

      inflight_update
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:status, "updating")
      |> Repo.update!()
    end)
  end

  def inflight_updates_for(%DeploymentGroup{} = deployment_group) do
    InflightUpdate
    |> where([iu], iu.deployment_id == ^deployment_group.id)
    |> preload([:device])
    |> Repo.all()
  end

  @doc """
  Count inflight updates for a deployment group, excluding priority queue updates.
  This ensures normal queue capacity is calculated independently.
  """
  def count_inflight_updates_for(%DeploymentGroup{} = deployment_group) do
    InflightUpdate
    |> where([iu], iu.deployment_id == ^deployment_group.id)
    |> where([iu], iu.priority_queue == false)
    |> Repo.aggregate(:count)
  end

  @doc """
  Count inflight updates that are in the priority queue for a deployment group.
  """
  @spec count_inflight_priority_updates_for(DeploymentGroup.t()) :: non_neg_integer()
  def count_inflight_priority_updates_for(%DeploymentGroup{} = deployment_group) do
    InflightUpdate
    |> where([iu], iu.deployment_id == ^deployment_group.id)
    |> where([iu], iu.priority_queue == true)
    |> Repo.aggregate(:count)
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

  defp broadcast_update_request(device_id, inflight_update, deployment_group) do
    Logger.metadata(device_id: device_id)

    device = get_device(device_id)

    opts =
      if proxy_url = get_in(deployment_group.org.settings.firmware_proxy_url) do
        [firmware_proxy_url: proxy_url]
      else
        []
      end

    update_payload = do_resolve_update(device, deployment_group, opts)

    device = %{device | deployment_group: deployment_group}

    DeviceEvents.schedule_update(device, inflight_update, update_payload)
  end

  @spec get_pinned_devices(non_neg_integer()) :: [Device.t()]
  def get_pinned_devices(user_id) do
    query =
      PinnedDevice
      |> where(user_id: ^user_id)
      |> select([:device_id])

    Device
    |> where([d], d.id in subquery(query))
    |> join(:left, [d], o in assoc(d, :org))
    |> join(:left, [d, o], p in assoc(d, :product))
    |> join(:left, [d, o, lc], lc in assoc(d, :latest_connection))
    |> join(:left, [d, o, lc, lh], lh in assoc(d, :latest_health))
    |> preload([d, o, p, lc, lh], org: o, product: p, latest_connection: lc, latest_health: lh)
    |> Repo.all()
  end

  @spec pin_device(non_neg_integer(), non_neg_integer()) ::
          {:ok, PinnedDevice.t()} | {:error, Ecto.Changeset.t()}
  def pin_device(user_id, device_id) do
    %{user_id: user_id, device_id: device_id}
    |> PinnedDevice.create()
    |> Repo.insert()
  end

  @spec unpin_device(neg_integer(), non_neg_integer()) ::
          {:ok, PinnedDevice.t()} | {:error, Ecto.Changeset.t()}
  def unpin_device(user_id, device_id) do
    PinnedDevice
    |> Repo.get_by!(user_id: user_id, device_id: device_id)
    |> Repo.delete()
  end

  def device_pinned?(user_id, device_id) do
    PinnedDevice
    |> where([p], p.user_id == ^user_id)
    |> where([p], p.device_id == ^device_id)
    |> Repo.exists?()
  end

  @doc """
  Unpins all devices belonging to user and org.
  """
  @spec unpin_org_devices(non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), nil | [term()]}
  def unpin_org_devices(user_id, org_id) do
    sub =
      Device
      |> where(org_id: ^org_id)
      |> select([:id])

    PinnedDevice
    |> where([p], p.user_id == ^user_id)
    |> where([p], p.device_id in subquery(sub))
    |> Repo.delete_all()
  end

  @doc """
  Get firmware or delta update URL.
  """
  @spec get_delta_or_firmware_url(Device.t(), DeploymentGroup.t()) ::
          {:ok, String.t()}
          | {:error, :delta_not_completed}
          | {:error, :device_does_not_support_deltas}
          | {:error, :delta_not_found}
  def get_delta_or_firmware_url(%Device{firmware_metadata: %{uuid: source_uuid}} = device, %DeploymentGroup{
        delta_updatable: true,
        firmware: %Firmware{delta_updatable: true} = target_firmware
      }) do
    case Firmwares.get_firmware_by_product_id_and_uuid(device.product_id, source_uuid) do
      {:ok, source_firmware} ->
        case get_delta_if_ready(device, source_firmware, target_firmware) do
          {:ok, delta} ->
            Firmwares.get_firmware_url(delta)

          {:device_delta_updatable, false} ->
            {:error, :device_does_not_support_deltas}

          {:delta, {:ok, %FirmwareDelta{}}} ->
            {:error, :delta_not_completed}

          {:delta, {:error, :not_found}} ->
            {:error, :delta_not_found}
        end

      {:error, :not_found} ->
        Firmwares.get_firmware_url(target_firmware)
    end
  end

  def get_delta_or_firmware_url(%Device{}, %DeploymentGroup{firmware: target}), do: Firmwares.get_firmware_url(target)

  @spec get_delta_if_ready(Device.t(), Firmware.t(), Firmware.t()) ::
          {:ok, FirmwareDelta.t()}
          | {:device_delta_updatable, false}
          | {:delta, {:ok, FirmwareDelta.t()}}
          | {:delta, {:error, :not_found}}
  defp get_delta_if_ready(device, source_firmware, target_firmware) do
    with {:device_delta_updatable, true} <-
           {:device_delta_updatable, delta_updatable?(device, target_firmware)},
         {:delta, {:ok, %{status: :completed} = delta}} <-
           {:delta,
            Firmwares.get_firmware_delta_by_source_and_target(
              source_firmware.id,
              target_firmware.id
            )} do
      {:ok, delta}
    end
  end

  @spec get_delta_url(Device.t(), Firmware.t()) ::
          {:ok, String.t()}
          | {:error, :failure}
  def get_delta_url(%Device{firmware_metadata: %{uuid: source_uuid}}, %Firmware{id: target_id, product_id: product_id}) do
    source_firmware_id_query =
      Firmware
      |> where(uuid: ^source_uuid)
      |> where(product_id: ^product_id)
      |> select([f], f.id)

    delta =
      FirmwareDelta
      |> where([fd], fd.source_id == subquery(source_firmware_id_query))
      |> where([fd], fd.target_id == ^target_id)
      |> Repo.one()

    Firmwares.get_firmware_url(delta)
  end

  @spec soft_deleted_devices_exist_for_product?(non_neg_integer()) :: boolean()
  def soft_deleted_devices_exist_for_product?(product_id) do
    from(d in Device,
      where: d.product_id == ^product_id,
      where: not is_nil(d.deleted_at)
    )
    |> Repo.exists?()
  end

  defp update_tool() do
    Application.get_env(
      :nerves_hub,
      :update_tool,
      # Fall back to old config key
      Application.get_env(:nerves_hub, :delta_updater, NervesHub.Firmwares.UpdateTool.Fwup)
    )
  end
end
