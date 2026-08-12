defmodule NervesHub.Devices do
  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.DeviceEvents
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.DeviceFiltering
  alias NervesHub.Devices.DeviceFirmwares
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.PinnedDevice
  alias NervesHub.Devices.SharedSecretAuth
  alias NervesHub.Extensions
  alias NervesHub.Filtering, as: CommonFiltering
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ProductNotifications
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  def get_device(device_id) when is_integer(device_id) do
    Repo.get(Device, device_id)
  end

  def get_device(device_id, preloads \\ []) do
    Device
    |> where(id: ^device_id)
    |> join_and_preload(preloads)
    |> Repo.one!()
  end

  def get_complete_device(device_id) do
    Device
    |> where([d], d.id == ^device_id)
    |> join(:left, [d], o in assoc(d, :org))
    |> join(:left, [d, o], p in assoc(d, :product))
    |> join(:left, [d, o, p], dg in assoc(d, :deployment_group))
    |> join(:left, [d, o, p, dg], cr in assoc(dg, :current_release))
    |> join(:left, [d, o, p, dg, cr], f in assoc(cr, :firmware))
    |> join(:left, [d, o, p, dg, cr, f], lc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:left, [d, o, p, dg, cr, f, lc], lh in assoc(d, :latest_health), as: :latest_health)
    |> preload([d, o, p, dg, cr, f, latest_connection: lc, latest_health: lh],
      org: o,
      product: p,
      deployment_group: {dg, current_release: {cr, firmware: f}},
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
    pagination =
      %{page: 1, page_size: 10}
      |> Map.merge(Map.get(opts, :pagination, %{}))

    sorting = Map.get(opts, :sort, {:asc, :identifier})
    filters = Map.get(opts, :filters, %{})

    flop = %Flop{page: pagination[:page], page_size: pagination[:page_size]}

    Device
    |> where([d], d.org_id == ^org_id)
    |> where([d], d.product_id == ^product_id)
    |> join(:left, [d], o in assoc(d, :org))
    |> join(:left, [d, o], p in assoc(d, :product))
    |> join(:left, [d, o, p], dg in assoc(d, :deployment_group))
    |> join(:left, [d, o, p, dg], cr in assoc(dg, :current_release))
    |> join(:left, [d, o, p, dg, cr], f in assoc(cr, :firmware))
    |> join(:left, [d, o, p, dg, cr, f], lc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:left, [d, o, p, dg, cr, f, lc], lh in assoc(d, :latest_health), as: :latest_health)
    |> Repo.exclude_deleted()
    |> DeviceFiltering.sort(sorting)
    |> DeviceFiltering.build_filters(filters)
    |> preload([d, o, p, dg, cr, f, latest_connection: lc, latest_health: lh],
      org: o,
      product: p,
      deployment_group: {dg, current_release: {cr, firmware: f}},
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
    common_filter_query(user)
    |> preload([latest_connection: lc], latest_connection: lc)
    |> preload([latest_health: lh], latest_health: lh)
    |> preload([deployment_group: dg], deployment_group: dg)
    |> preload([inflight_update: ifu], inflight_update: ifu)
    |> CommonFiltering.filter(product, opts)
  end

  @spec filter_query(Product.t(), User.t(), map()) :: Ecto.Query.t()
  def filter_query(product, user, opts) do
    common_filter_query(user)
    |> CommonFiltering.filter_query(product, opts)
  end

  defp common_filter_query(user) do
    Device
    |> join(:left, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:left, [d, dc], dh in assoc(d, :latest_health), as: :latest_health)
    |> join(:left, [d, dc, dh], pd in PinnedDevice,
      on: pd.device_id == d.id and pd.user_id == ^user.id,
      as: :pinned
    )
    |> join(:left, [d], dg in assoc(d, :deployment_group), as: :deployment_group)
    |> join(:left, [d], ifu in assoc(d, :inflight_update), as: :inflight_update)
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
    |> Repo.fetch()
  end

  @spec get_by_identifier!(String.t()) :: Device.t()
  def get_by_identifier!(identifier) when is_binary(identifier) do
    Device
    |> join(:left, [d], o in assoc(d, :org), as: :org)
    |> where(identifier: ^identifier)
    |> preload([org: o], org: o)
    |> join_and_preload_deployment_group_and_current_release()
    |> join_and_preload([:product, :latest_connection])
    |> Repo.one!()
  end

  @spec get_by_identifier!(
          scope :: Scope.t(),
          identifier :: String.t(),
          preload_assocs :: atom() | list(atom()) | nil
        ) ::
          Device.t()
  def get_by_identifier!(scope, identifier, preload_assoc \\ [:product, :latest_connection])

  def get_by_identifier!(%Scope{} = scope, identifier, preload_assoc) when is_binary(identifier) do
    get_by_identifier_query(scope, identifier, preload_assoc)
    |> Repo.one!()
  end

  @spec get_by_identifier(
          scope :: Scope.t(),
          identifier :: String.t(),
          preload_assocs :: atom() | list(atom()) | nil
        ) ::
          {:ok, Device.t()} | {:error, :not_found}
  def get_by_identifier(%Scope{} = scope, identifier, preload_assoc \\ [:product, :latest_connection])
      when is_binary(identifier) do
    get_by_identifier_query(scope, identifier, preload_assoc)
    |> Repo.fetch()
  end

  defp get_by_identifier_query(%Scope{org: org}, identifier, preload_assoc) when not is_nil(org) do
    Device
    |> join(:left, [d], o in assoc(d, :org), as: :org)
    |> where(identifier: ^identifier)
    |> where(org_id: ^org.id)
    |> preload([org: o], org: o)
    |> join_and_preload_deployment_group_and_current_release()
    |> join_and_preload(preload_assoc)
  end

  defp get_by_identifier_query(%Scope{user: user}, identifier, preload_assoc) when not is_nil(user) do
    Device
    |> join(:left, [d], o in assoc(d, :org), as: :org)
    |> join(:left, [d, o], u in assoc(o, :users), as: :users)
    |> where(identifier: ^identifier)
    |> where([users: u], u.id == ^user.id)
    |> preload([org: o], org: o)
    |> join_and_preload_deployment_group_and_current_release()
    |> join_and_preload(preload_assoc)
  end

  @doc """
  Fetch a device by identifier, preloading its org, product, latest connection,
  deployment group and current release. Raises if the device does not exist.
  """
  def get_by_identifier_with_deployment_and_release!(identifier) do
    Device
    |> where(identifier: ^identifier)
    |> join_and_preload_deployment_group_and_current_release()
    |> preload([:org, :product, :latest_connection])
    |> Repo.one!()
  end

  defp join_and_preload_deployment_group_and_current_release(query) do
    query
    |> join(:left, [d], dp in assoc(d, :deployment_group), as: :deployment_group)
    |> join(:left, [deployment_group: dg], cr in assoc(dg, :current_release), as: :current_release)
    |> join(:left, [current_release: cr], f in assoc(cr, :firmware), as: :firmware)
    |> preload([deployment_group: dg, firmware: f, current_release: cr],
      deployment_group: {dg, current_release: {cr, firmware: f}}
    )
  end

  defp join_and_preload(query, assocs) when is_list(assocs) do
    Enum.reduce(assocs, query, fn assoc, q ->
      join_and_preload(q, assoc)
    end)
  end

  defp join_and_preload(query, nil), do: query

  defp join_and_preload(query, :deployment) do
    join_and_preload_deployment_group_and_current_release(query)
  end

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

  @spec get_shared_secret_auth(String.t()) ::
          {:ok, SharedSecretAuth.t()} | {:error, :not_found}
  def get_shared_secret_auth(key) do
    SharedSecretAuth
    |> join(:inner, [ssa], d in assoc(ssa, :device))
    |> join(:inner, [ssa, d], p in assoc(d, :product))
    |> where([ssa], ssa.key == ^key)
    |> where([ssa], is_nil(ssa.deactivated_at))
    |> where([_, d], is_nil(d.deleted_at))
    |> preload([ssa, d, p], [:product_shared_secret_auth, device: {d, product: p}])
    |> Repo.fetch()
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
    |> Repo.transact()
    |> case do
      {:ok, %{device: device}} -> {:ok, device}
      error -> error
    end
  end

  def destroy_device(%Device{} = device) do
    Repo.delete(device)
  end

  def clean_up_soft_deleted_devices() do
    twelve_days_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -12, :day)

    Device
    |> where([d], d.deleted_at < ^twelve_days_ago)
    |> Repo.all()
    |> Enum.each(fn device ->
      Repo.transact(fn ->
        case destroy_device(device) do
          {:ok, device} ->
            _ = ProductNotifications.create_soft_deleted_device_removed!(device)
            {:ok, device}

          error ->
            {:error, "Error removing soft-deleted device: #{inspect(error)}"}
        end
      end)
    end)
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
    |> join(:inner, [dep], cr in assoc(dep, :current_release))
    |> join(:inner, [_, dev], f in Firmware, on: f.uuid == fragment("?.firmware_metadata->>'uuid'", dev))
    # Exclude the current firmware, we don't need to generate that one
    |> where([_, _, cr, f], f.id != cr.firmware_id)
    |> select([_, _, cr, f], {f.id, cr.firmware_id})
    |> distinct(true)
    |> Repo.all()
  end

  @spec update_firmware_metadata(
          device :: Device.t(),
          connecting_metadata :: FirmwareMetadata.t() | nil,
          validation_status :: Device.firmware_validation_statuses(),
          auto_revert_detected? :: boolean()
        ) ::
          {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update_firmware_metadata(device, nil, validation_status, auto_revert_detected?) do
    Repo.transact(fn ->
      attrs = %{
        firmware_validation_status: validation_status,
        firmware_auto_revert_detected: auto_revert_detected?
      }

      attrs =
        case device.firmware_metadata do
          nil ->
            # Device joined without any known firmware metadata (e.g. its
            # uboot env had no `nerves_fw_uuid`). Nothing to report against,
            # so just persist the device-level values. This is unexpected,
            # so raise a product notification to surface it.
            _ = ProductNotifications.create_missing_firmware_metadata_notification!(device)
            attrs

          current_metadata ->
            firmware_metadata = Map.from_struct(current_metadata)

            DeviceFirmwares.add_or_update_reported_firmware(
              device,
              firmware_metadata,
              validation_status,
              auto_revert_detected?
            )
            |> case do
              :ok -> attrs
              {:ok, df} -> Map.put(attrs, :current_device_firmware_id, df.id)
            end
        end

      update_device(device, attrs)
    end)
  end

  def update_firmware_metadata(device, updated_metadata, validation_status, auto_revert_detected?) do
    Repo.transact(fn ->
      DeviceTemplates.audit_firmware_metadata_updated(device)

      updated_metadata =
        Map.new(updated_metadata, fn {k, v} ->
          if is_atom(k), do: {k, v}, else: {String.to_existing_atom(k), v}
        end)

      metadata =
        if is_nil(device.firmware_metadata) do
          updated_metadata
        else
          device.firmware_metadata
          |> Map.from_struct()
          |> Map.merge(updated_metadata)
        end

      with {:ok, device_firmware} <-
             DeviceFirmwares.add_reported_firmware(
               device,
               metadata,
               validation_status,
               auto_revert_detected?
             ) do
        update_device(device, %{
          firmware_metadata: metadata,
          firmware_validation_status: validation_status,
          firmware_auto_revert_detected: auto_revert_detected?,
          current_device_firmware_id: device_firmware.id
        })
      end
    end)
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
  # No-op if the deployment group ID matches the current deployment ID
  def update_deployment_group(%{deployment_id: deployment_id} = device, %{id: deployment_id}) do
    device
  end

  def update_deployment_group(device, deployment_group) do
    # Use a transaction to ensure device update and delta generation happen atomically
    # This prevents race condition: when the transaction commits, both the device's new
    # deployment_id and any firmware_delta rows (with :processing status) become visible
    # simultaneously, preventing the orchestrator from scheduling a full update when a delta
    # is being prepared
    {:ok, device} =
      Repo.transact(fn ->
        # Update the device's deployment group first
        updated_device =
          device
          |> Device.update_deployment_group(deployment_group)
          |> Repo.update!()

        # Then queue delta generation for any new device firmware combinations
        # This will pick up the newly added device's firmware
        _ = ManagedDeployments.trigger_delta_generation_for_deployment_group(deployment_group)

        {:ok, updated_device}
      end)

    # notify the device about its assigned deployment group changing
    DeviceEvents.deployment_assigned(device)

    # let the orchestrator know that a device has been added to the deployment group
    DeploymentOrchestratorEvents.device_added(device)

    Map.put(device, :deployment_group, deployment_group)
  end

  @spec clear_deployment_group(Device.t()) :: Device.t()
  def clear_deployment_group(device) do
    device =
      device
      |> Device.clear_deployment_group()
      |> Repo.update!()

    DeviceEvents.deployment_cleared(device)

    Map.put(device, :deployment_group, nil)
  end

  def deployment_device_online(%DeviceInfo{deployment_id: nil}) do
    :ok
  end

  def deployment_device_online(device_info) do
    firmware_uuid = if(device_info.firmware_metadata, do: device_info.firmware_metadata.uuid)

    payload = %{
      updates_enabled: device_info.device_updates_enabled,
      updates_blocked_until: device_info.device_updates_blocked_until,
      firmware_uuid: firmware_uuid
    }

    DeploymentOrchestratorEvents.device_online(device_info, payload)

    :ok
  end

  def up_to_date_count(%DeploymentGroup{} = deployment_group) do
    Device
    |> where([d], d.deployment_id == ^deployment_group.id)
    |> where([d], d.updates_enabled == true)
    |> where([d], d.firmware_metadata["uuid"] == ^deployment_group.current_release.firmware.uuid)
    |> Repo.exclude_deleted()
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
    |> where([d], d.updates_enabled == true)
    |> where(
      [d],
      is_nil(d.firmware_metadata) or
        d.firmware_metadata["uuid"] != ^deployment_group.current_release.firmware.uuid
    )
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  @spec updates_disabled_count(DeploymentGroup.t()) :: non_neg_integer()
  def updates_disabled_count(%DeploymentGroup{id: id}) do
    Device
    |> where([d], d.deployment_id == ^id)
    |> where([d], d.updates_enabled == false)
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  @spec in_penalty_box_count(DeploymentGroup.t(), DateTime.t()) :: non_neg_integer()
  def in_penalty_box_count(%DeploymentGroup{id: id}, now \\ DateTime.utc_now()) do
    Device
    |> where([d], d.deployment_id == ^id)
    |> where([d], not is_nil(d.updates_blocked_until) and d.updates_blocked_until > ^now)
    |> Repo.exclude_deleted()
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

    _ = Accounts.maybe_copy_firmware_keys(device, product.org)

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
    |> Repo.transact()
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

  @doc """
  Returns the sorted, distinct list of tags used by all devices in a product.

  Used to power tag autocomplete suggestions when tagging devices or targeting
  deployment groups.
  """
  @spec distinct_tags_for_product(Product.t()) :: [String.t()]
  def distinct_tags_for_product(%Product{} = product) do
    Device
    |> where([d], d.product_id == ^product.id)
    |> where([d], not is_nil(d.tags))
    |> select([d], fragment("distinct unnest(?)", d.tags))
    |> Repo.all()
    |> Enum.sort()
  end

  @spec add_tag(Device.t(), User.t(), String.t()) :: {:ok, Device.t()} | {:error, any()} | {:error, any(), any(), any()}
  def add_tag(%Device{} = device, user, tag) do
    tag = String.trim(tag)

    if tag == "" or String.contains?(tag, " ") do
      {:error, "Tags cannot be empty or contain spaces."}
    else
      current_tags = device.tags || []

      if tag in current_tags do
        {:error, "Tag \"#{tag}\" already exists on this device."}
      else
        new_tags = current_tags ++ [tag]
        tag_device(device, user, new_tags)
      end
    end
  end

  @spec remove_tag(Device.t(), User.t(), String.t()) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def remove_tag(%Device{} = device, user, tag) do
    current_tags = device.tags || []
    new_tags = List.delete(current_tags, tag)

    tag_device(device, user, new_tags)
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
    |> Repo.transact()
    |> case do
      {:ok, %{update_with_audit: updated}} ->
        DeviceEvents.updated(device)
        {:ok, updated}

      err ->
        err
    end
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

  @spec get_devices_by_id(Scope.t(), [non_neg_integer()]) :: [Device.t()]
  def get_devices_by_id(%Scope{user: user}, ids) when is_list(ids) do
    Device
    |> join(:left, [d], o in assoc(d, :org), as: :org)
    |> join(:left, [d, o], u in assoc(o, :users), as: :users)
    |> where([d], d.id in ^ids)
    |> where([users: u], u.id == ^user.id)
    |> Repo.all()
  end

  defp maybe_broadcast_updated(device, opts) do
    if Keyword.get(opts, :broadcast, true) do
      DeviceEvents.updated(device)
    else
      :ok
    end
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
  Get distinct device architectures based on the product
  """
  def architectures(product_id) do
    Device
    |> select([d], fragment("?->>'architecture'", d.firmware_metadata))
    |> distinct(true)
    |> where([d], d.product_id == ^product_id)
    |> order_by([d], fragment("?->>'architecture'", d.firmware_metadata))
    |> Repo.all()
  end

  @doc """
  Get distinct tags currently used across devices in the product
  """
  def distinct_tags(product_id) do
    Device
    |> select([d], fragment("unnest(?)", d.tags))
    |> distinct(true)
    |> where([d], d.product_id == ^product_id)
    |> order_by([d], fragment("unnest(?)", d.tags))
    |> Repo.all()
  end

  def fetch_connecting_code(device_id) do
    Device
    |> join(:left, [d], dp in assoc(d, :deployment_group))
    |> select([d, dp], {d.connecting_code, dp.connecting_code})
    |> where(id: ^device_id)
    |> Repo.one!()
  end

  def enable_extension_setting(%Device{} = device, extension_string) do
    set_extension_setting(device, extension_string, true)
  end

  def disable_extension_setting(%Device{} = device, extension_string) do
    set_extension_setting(device, extension_string, false)
  end

  defp set_extension_setting(%Device{} = device, extension_string, enabled?) do
    device = get_device(device.id)
    event = if enabled?, do: "attach", else: "detach"

    Device.changeset(device, %{"extensions" => %{extension_string => enabled?}})
    |> Repo.update()
    |> tap(fn
      {:ok, _} ->
        Extensions.broadcast_extension_event(device, event, extension_string)

      _ ->
        :nope
    end)
  end

  @doc """
  Get firmware or delta.
  """

  @spec soft_deleted_devices_exist_for_product?(non_neg_integer()) :: boolean()
  def soft_deleted_devices_exist_for_product?(product_id) do
    from(d in Device,
      where: d.product_id == ^product_id,
      where: not is_nil(d.deleted_at)
    )
    |> Repo.exists?()
  end

  def online_count(product) do
    Device
    |> join(:left, [d], lc in assoc(d, :latest_connection))
    |> where(product_id: ^product.id)
    |> where([_, lc], lc.status == :connected)
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  def offline_count(product) do
    Device
    |> join(:left, [d], lc in assoc(d, :latest_connection))
    |> where(product_id: ^product.id)
    |> where([_, lc], lc.status != :connected or is_nil(lc))
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  def not_seen_in_x_days_count(product, days) do
    x_days_ago = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days, :day)

    Device
    |> join(:left, [d], lc in assoc(d, :latest_connection))
    |> where(product_id: ^product.id)
    |> where(
      [_, lc],
      is_nil(lc) or (lc.status != :connected and lc.disconnected_at < ^x_days_ago)
    )
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  def total_count(product) do
    Device
    |> where(product_id: ^product.id)
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end
end
