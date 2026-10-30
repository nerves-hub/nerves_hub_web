defmodule NervesHub.Devices.BulkActions do
  import Ecto.Query

  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.Certificate
  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.BulkImport
  alias NervesHub.Devices.Certificates
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Updates
  alias NervesHub.Extensions
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ProductNotifications
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.TaskSupervisor, as: Tasks

  def async_bulk_create(org_id, product_id, import_list, format, tags \\ [])

  def async_bulk_create(org_id, product_id, import_list, format, tags) when not is_binary(import_list) do
    async_bulk_create(org_id, product_id, JSON.encode!(import_list), format, tags)
  end

  def async_bulk_create(org_id, product_id, import_list, format, tags) do
    Task.Supervisor.start_child(Tasks, fn ->
      {successful_count, unsuccessful_count} = bulk_create(org_id, product_id, import_list, format, tags)

      _ =
        ProductNotifications.create_device_async_bulk_create_notification!(
          product_id,
          successful_count,
          unsuccessful_count,
          format
        )
    end)
    |> case do
      :ignore -> {:error, :ignored}
      {:error, _} = error -> error
      {:ok, pid, _info} -> {:ok, pid}
      ok -> ok
    end
  end

  def bulk_create(org_id, product_id, import_list, format, tags \\ []) do
    product =
      Product
      |> where(org_id: ^org_id, id: ^product_id)
      |> Repo.exclude_deleted()
      |> Repo.one!()

    BulkImport.parse_file(format, import_list)
    |> Enum.map(fn details ->
      changeset =
        Device.changeset(%Device{}, %{
          org_id: product.org_id,
          product_id: product.id,
          identifier: details.device_identifier,
          tags: tags,
          managed_updates_allowed: product.default_managed_updates_allowed
        })

      Repo.transact(fn ->
        with {:ok, device} <- Repo.insert(changeset),
             {:ok, pem} <- details.pem,
             {:ok, otp_cert} <- Certificate.from_pem_or_der(pem),
             {:ok, _db_cert} <- Certificates.create_device_certificate(device, otp_cert) do
          {:ok, device}
        end
      end)
    end)
    |> Enum.frequencies_by(fn result -> elem(result, 0) end)
    |> then(fn res ->
      {Map.get(res, :ok, 0), Map.get(res, :error, 0)}
    end)
  end

  @spec tag_devices([Device.t()] | Ecto.Query.t(), User.t(), list(String.t())) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def tag_devices(devices, user, tags) when is_list(devices) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :tag_device, [&1, user, tags]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def tag_devices(%Ecto.Query{} = devices_query, user, tags) do
    stream_processing(devices_query, {Devices, :tag_device, [user, tags]})
  end

  @doc """
  Add tags to many devices, keeping the tags each device already has.

  `tag_devices/3` replaces the tags on every device it touches, which is no use
  for putting one shared tag on a fleet of individually tagged devices.
  """
  @spec add_tags_to_devices([Device.t()] | Ecto.Query.t(), User.t(), list(String.t()) | String.t()) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def add_tags_to_devices(devices, user, tags) when is_list(devices) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :add_tags, [&1, user, tags]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def add_tags_to_devices(%Ecto.Query{} = devices_query, user, tags) do
    stream_processing(devices_query, {Devices, :add_tags, [user, tags]})
  end

  @doc """
  Remove tags from many devices, leaving the rest of each device's tags alone.
  """
  @spec remove_tags_from_devices([Device.t()] | Ecto.Query.t(), User.t(), list(String.t()) | String.t()) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def remove_tags_from_devices(devices, user, tags) when is_list(devices) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :remove_tags, [&1, user, tags]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def remove_tags_from_devices(%Ecto.Query{} = devices_query, user, tags) do
    stream_processing(devices_query, {Devices, :remove_tags, [user, tags]})
  end

  @doc """
  Remove multiple devices from their deployment groups.

  Returns `{:ok, count}` with the number of devices updated.
  """
  @spec remove_many_from_deployment_group({[non_neg_integer()], Product.t()} | Ecto.Query.t()) ::
          %{ok: non_neg_integer(), error: non_neg_integer()} | %{ok: non_neg_integer()}
  def remove_many_from_deployment_group({device_ids, product} = args) when is_tuple(args) do
    {count, _} =
      Device
      |> Repo.exclude_deleted()
      |> where([d], d.id in ^device_ids)
      |> where([d], d.product_id == ^product.id)
      |> where([d], not is_nil(d.deployment_id))
      |> Repo.update_all(set: [deployment_id: nil])

    Enum.each(device_ids, &DeviceEvents.updated(%Device{id: &1}))

    %{ok: count}
  end

  def remove_many_from_deployment_group(%Ecto.Query{} = devices_query) do
    stream_processing(devices_query, fn device ->
      device
      |> Device.clear_deployment_group()
      |> Repo.update()
      |> case do
        {:ok, device} = res ->
          DeviceEvents.deployment_cleared(device)
          res

        res ->
          res
      end
    end)
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
          [non_neg_integer()] | Ecto.Query.t(),
          DeploymentGroup.t() | non_neg_integer(),
          User.t()
        ) ::
          %{updated: non_neg_integer(), ignored: non_neg_integer()}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def move_many_to_deployment_group(devices, %DeploymentGroup{id: deployment_id}, user) do
    move_many_to_deployment_group(devices, deployment_id, user)
  end

  def move_many_to_deployment_group(device_ids, deployment_id, user) when is_list(device_ids) do
    deployment_group =
      DeploymentGroup
      |> from(as: :deployment_group)
      |> join(:inner, [deployment_group: dg], o in assoc(dg, :org), as: :org)
      |> join(:inner, [org: o], u in assoc(o, :users), as: :users)
      |> ManagedDeployments.join_current_release()
      |> join(:inner, [current_release: cr], f in assoc(cr, :firmware), as: :firmware)
      |> where([deployment_group: dg], dg.id == ^deployment_id)
      |> where([users: users], users.id == ^user.id)
      |> preload([firmware: f, current_release: cr],
        current_release: {cr, firmware: f}
      )
      |> Repo.one!()

    # Use a transaction to ensure devices are updated and deltas are queued atomically
    # This minimizes the race condition window where the orchestrator could pick up devices
    # before their firmware_delta rows are created
    {:ok, {devices_updated_count, _}} =
      Repo.transact(fn ->
        {count, _} =
          Device
          |> join(:inner, [d], o in assoc(d, :org), as: :org)
          |> join(:inner, [org: o], u in assoc(o, :users), as: :users)
          |> where([users: users], users.id == ^user.id)
          |> Repo.exclude_deleted()
          |> where([d], d.id in ^device_ids)
          |> where(
            [d],
            d.firmware_metadata["platform"] == ^deployment_group.current_release.firmware.platform
          )
          |> where(
            [d],
            d.firmware_metadata["architecture"] ==
              ^deployment_group.current_release.firmware.architecture
          )
          |> Repo.update_all([set: [deployment_id: deployment_id]], timeout: to_timeout(minute: 2))

        # Queue delta generation for any new device firmware combinations immediately
        # after the device updates within the same transaction
        _ = ManagedDeployments.trigger_delta_generation_for_deployment_group(deployment_group)

        {:ok, {count, nil}}
      end)

    :ok = Enum.each(device_ids, &DeviceEvents.updated(%Device{id: &1}))

    # let the orchestrator know that some devices have been added to the deployment group
    DeploymentOrchestratorEvents.bulk_devices_added(deployment_group)

    %{updated: devices_updated_count, ignored: length(device_ids) - devices_updated_count}
  end

  def move_many_to_deployment_group(%Ecto.Query{} = devices_query, deployment_id, user) do
    deployment_group =
      DeploymentGroup
      |> from(as: :deployment_group)
      |> join(:inner, [deployment_group: dg], o in assoc(dg, :org), as: :org)
      |> join(:inner, [org: o], u in assoc(o, :users), as: :users)
      |> ManagedDeployments.join_current_release()
      |> join(:inner, [current_release: cr], f in assoc(cr, :firmware), as: :firmware)
      |> where([deployment_group: dg], dg.id == ^deployment_id)
      |> where([users: users], users.id == ^user.id)
      |> preload([firmware: f, current_release: cr],
        current_release: {cr, firmware: f}
      )
      |> Repo.one!()

    devices_query
    |> where(
      [d],
      d.firmware_metadata["platform"] == ^deployment_group.current_release.firmware.platform or
        is_nil(d.firmware_metadata)
    )
    |> where(
      [d],
      d.firmware_metadata["architecture"] ==
        ^deployment_group.current_release.firmware.architecture or is_nil(d.firmware_metadata)
    )
    |> stream_processing(
      fn device ->
        device
        |> Device.update_deployment_group(deployment_group)
        |> Repo.update()
        |> case do
          {:ok, device} ->
            DeviceEvents.updated(device)
            :ok

          _ ->
            :error
        end
      end,
      before_commit: fn ->
        _ = ManagedDeployments.trigger_delta_generation_for_deployment_group(deployment_group)
        DeploymentOrchestratorEvents.bulk_devices_added(deployment_group)
      end
    )
  end

  @spec move_many_to_deployment_group_by_identifiers(
          Product.t(),
          [String.t()],
          DeploymentGroup.t() | non_neg_integer(),
          User.t()
        ) :: %{ok: non_neg_integer(), error: non_neg_integer()}
  def move_many_to_deployment_group_by_identifiers(product, identifiers, deployment_group, user) do
    Device
    |> Repo.exclude_deleted()
    |> where([d], d.product_id == ^product.id)
    |> where([d], d.identifier in ^identifiers)
    |> move_many_to_deployment_group(deployment_group, user)
  end

  @spec move_many([Device.t()] | Ecto.Query.t(), Product.t(), User.t()) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def move_many(devices, target_product, user) when is_list(devices) do
    product = Repo.preload(target_product, :org)

    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :move, [&1, product, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def move_many(%Ecto.Query{} = devices_query, target_product, user) do
    stream_processing(devices_query, {Devices, :move, [target_product, user]})
  end

  @spec enable_updates_for_devices([Device.t()] | Ecto.Query.t(), User.t()) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def enable_updates_for_devices(devices, user) when is_list(devices) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Updates, :enable_updates, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def enable_updates_for_devices(%Ecto.Query{} = devices_query, user) do
    stream_processing(devices_query, {Updates, :enable_updates, [user]})
  end

  @spec disable_updates_for_devices([Device.t()] | Ecto.Query.t(), User.t()) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def disable_updates_for_devices(devices, user) when is_list(devices) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Updates, :disable_updates, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def disable_updates_for_devices(%Ecto.Query{} = devices_query, user) do
    stream_processing(devices_query, {Updates, :disable_updates, [user]})
  end

  @doc """
  Put many devices into one update mode.

  The general form of `enable_updates_for_devices/2` and
  `disable_updates_for_devices/2`, which remain as the two-state shortcuts the
  existing bulk buttons use.
  """
  @spec set_update_mode_for_devices([Device.t()] | Ecto.Query.t(), Device.update_mode(), User.t()) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def set_update_mode_for_devices(devices, mode, user) when is_list(devices) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Updates, :set_update_mode, [&1, mode, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def set_update_mode_for_devices(%Ecto.Query{} = devices_query, mode, user) do
    stream_processing(devices_query, {Updates, :set_update_mode, [mode, user]})
  end

  @doc """
  Allow or forbid many devices putting themselves into `:device_managed`.

  Because the grant defaults to off, this is how a fleet is opted into managing
  its own updates without visiting every device.
  """
  @spec set_managed_updates_allowed_for_devices([Device.t()] | Ecto.Query.t(), boolean(), User.t()) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def set_managed_updates_allowed_for_devices(devices, enabled, user) when is_list(devices) do
    Enum.map(
      devices,
      &Task.Supervisor.async(Tasks, Updates, :set_managed_updates_allowed, [&1, enabled, user])
    )
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def set_managed_updates_allowed_for_devices(%Ecto.Query{} = devices_query, enabled, user) do
    stream_processing(devices_query, {Updates, :set_managed_updates_allowed, [enabled, user]})
  end

  @doc """
  Allow or forbid every device in a product putting itself into `:device_managed`.

  Only devices whose grant differs are touched, so the counts are of devices that
  changed. Each goes through `Updates.set_managed_updates_allowed/3`, which
  audits the change against the device and tells its connection.

  Each device commits on its own, a chunk of devices loaded at a time, rather
  than inside one transaction as `set_managed_updates_allowed_for_devices/3`
  does with a query. A connection re-reads its device when told it changed, and
  told before the change commits it reads the old grant and keeps showing it
  until it reconnects.
  """
  @spec set_managed_updates_allowed_for_product(Product.t(), boolean(), User.t()) ::
          %{ok: non_neg_integer(), error: non_neg_integer()}
  def set_managed_updates_allowed_for_product(%Product{} = product, enabled, user) when is_boolean(enabled) do
    Device
    |> where([d], d.product_id == ^product.id)
    |> where([d], d.managed_updates_allowed != ^enabled)
    |> Repo.exclude_deleted()
    |> select([d], d.id)
    |> Repo.all()
    |> Stream.chunk_every(500)
    |> Stream.flat_map(fn ids -> Repo.all(from(d in Device, where: d.id in ^ids)) end)
    |> Enum.reduce(%{ok: 0, error: 0}, fn device, acc ->
      case Updates.set_managed_updates_allowed(device, enabled, user) do
        {:ok, _device} -> %{acc | ok: acc.ok + 1}
        _error -> %{acc | error: acc.error + 1}
      end
    end)
  end

  @doc """
  Turn one extension on or off for every device in a product.

  This is the device-level setting, so it takes effect only while the product
  allows the extension too. With the product's own setting off it is recorded,
  and applies once the product turns the extension on. Devices that already
  have the requested setting are left alone and not counted.

  It is one statement rather than a device at a time: a device's extension
  setting is not audited and carries no session state, so there is nothing per
  device to keep in step. The change is audited once against the product, and
  connected devices hear of it through the product-wide fan-out the product's
  own extension setting uses.
  """
  @spec set_extension_for_product(Product.t(), Extensions.extension() | String.t(), boolean(), User.t()) ::
          {:ok, non_neg_integer()} | {:error, :unknown_extension}
  def set_extension_for_product(%Product{} = product, extension, enabled, user) when is_boolean(enabled) do
    key = to_string(extension)

    case Enum.find(Extensions.list(), &(to_string(&1) == key)) do
      nil ->
        {:error, :unknown_extension}

      extension ->
        now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

        {:ok, count} =
          Repo.transact(fn ->
            {count, _} =
              Device
              |> where([d], d.product_id == ^product.id)
              |> Repo.exclude_deleted()
              # A device with no value for the key has the embed's default, which is on.
              |> where(
                [d],
                fragment("coalesce((?->>?::text)::boolean, true) <> ?::boolean", d.extensions, ^key, ^enabled)
              )
              |> update([d],
                set: [
                  extensions: fragment("? || jsonb_build_object(?::text, ?::boolean)", d.extensions, ^key, ^enabled),
                  updated_at: ^now
                ]
              )
              |> Repo.update_all([])

            if count > 0, do: ProductTemplates.audit_extension_set_for_devices(user, product, key, enabled, count)

            {:ok, count}
          end)

        # Read now rather than trusted from the caller, whose copy may predate a
        # change to the product's setting.
        %Product{extensions: product_settings} = Repo.reload!(product)

        if count > 0 and product_settings[extension] == true do
          Extensions.broadcast_extension_event(product, if(enabled, do: "attach", else: "detach"), key)
        end

        {:ok, count}
    end
  end

  @spec clear_penalty_box_for_devices([Device.t()] | Ecto.Query.t(), User.t()) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def clear_penalty_box_for_devices(devices, user) when is_list(devices) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Updates, :clear_penalty_box, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def clear_penalty_box_for_devices(%Ecto.Query{} = devices_query, user) do
    stream_processing(devices_query, {Updates, :clear_penalty_box, [user]})
  end

  defp stream_processing(devices_query, fun, opts \\ []) do
    stream = Repo.stream(devices_query)

    Repo.transact(
      fn ->
        stream
        |> Stream.map(fn device ->
          case fun do
            {module, fun_name, args} ->
              apply(module, fun_name, [device | args])

            fun ->
              fun.(device)
          end
        end)
        |> Enum.reduce(%{ok: 0, error: 0}, fn
          :ok, acc -> %{acc | ok: acc.ok + 1}
          {:ok, _updated}, acc -> %{acc | ok: acc.ok + 1}
          :error, acc -> %{acc | error: acc.error + 1}
          {:error, _changeset}, acc -> %{acc | error: acc.error + 1}
          {:error, _name, _changeset, _}, acc -> %{acc | error: acc.error + 1}
        end)
        |> then(fn res ->
          if opts[:before_commit], do: opts[:before_commit].()
          {:ok, res}
        end)
      end,
      timeout: 60_000
    )
    |> case do
      {:ok, res} -> res
    end
  end
end
