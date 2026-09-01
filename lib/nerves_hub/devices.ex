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
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.DeviceFiltering
  alias NervesHub.Devices.DeviceFirmwares
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Devices.NetworkIdentity
  alias NervesHub.Devices.PinnedDevice
  alias NervesHub.Devices.SharedSecretAuth
  alias NervesHub.Extensions
  alias NervesHub.Filtering, as: CommonFiltering
  alias NervesHub.Firmwares.FirmwareMetadata
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
    |> preload(latest_health: ^health_status_query())
    |> preload([deployment_group: dg], deployment_group: dg)
    |> preload([inflight_update: ifu], inflight_update: ifu)
    |> CommonFiltering.filter(product, opts)
  end

  # The device list renders the health icon and its tooltip, and nothing else
  # off `latest_health` - but the row carries every metric the device last
  # reported in `data`. Preloading from a narrowed query rather than the joined
  # binding leaves that payload in the database. The join itself stays: the
  # alarm and health status filters read `data` from it in SQL.
  defp health_status_query() do
    from(dh in DeviceHealth, select: [:id, :status, :status_reasons])
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

  defp join_and_preload(query, :network_identities) do
    query
    |> join(:left, [d], ei in assoc(d, :network_identities), as: :network_identities)
    |> preload([network_identities: ei], network_identities: ei)
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

    # A device is only soft deleted, so these have to go explicitly: otherwise
    # they keep holding the (service, identifier) unique index and reprovisioning
    # the same hardware collides with the identity of the device just deleted.
    network_identities_query = from(ei in NetworkIdentity, where: ei.device_id == ^device.id)

    changeset = Repo.soft_delete_changeset(device)

    Multi.new()
    |> Multi.delete_all(:device_certificates, device_certificates_query)
    |> Multi.delete_all(:pinned_devices, pinned_devices_query)
    |> Multi.delete_all(:network_identities, network_identities_query)
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
    # The device's identities on other networks name an organisation of their
    # own, and that is what those networks resolve a key to. Left behind, this
    # device would keep answering for the organisation it just left — and be
    # placed on that organisation's network by anything using them. Same
    # transaction as the move, so there is no window where the two disagree.
    |> Multi.update_all(
      :network_identities,
      from(ei in NetworkIdentity, where: ei.device_id == ^device.id),
      set: [org_id: product.org_id, updated_at: DateTime.utc_now(:second)]
    )
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

  @doc """
  Update a device and record who did it.

  The actor is usually a user, but a device is one too: a device that sets its
  own update mode, or that is moved off a mode its firmware cannot support, is
  the actor for that change, and the log should not imply an operator asked.
  """
  @spec update_device_with_audit(Device.t(), map(), User.t() | Device.t(), String.t()) ::
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
