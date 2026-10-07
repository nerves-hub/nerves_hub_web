defmodule NervesHub.Devices.BulkActions do
  import Ecto.Query

  alias NervesHub.Accounts.User
  alias NervesHub.Certificate
  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.BulkImport
  alias NervesHub.Devices.Certificates
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Updates
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
          tags: tags
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

  # How many devices each transaction of a move holds. One statement for a whole
  # fleet holds a lock on every row it touches until the last is written, and
  # anything else writing to those devices waits that long, so a move commits a
  # chunk at a time instead.
  @move_chunk_size 5_000

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
    deployment_group = get_deployment_group_for_move!(deployment_id, user)

    {moved_device_ids, _selected} =
      device_ids
      |> Enum.chunk_every(@move_chunk_size)
      |> move_chunks(deployment_group, user)

    devices_updated_count = length(moved_device_ids)

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

  # Each chunk is its own transaction: its devices are moved and their deltas
  # queued together, so the orchestrator never sees a moved device without the
  # delta it should wait for. Queuing looks at the whole group each time, which
  # on 190,000 devices took 52ms, so a 190,000-device move spends at most about
  # 2s on it across its 38 chunks.
  #
  # The devices only hear about it once every chunk is in. If a chunk fails, the
  # ones before it stay moved, so their devices and the orchestrator are still
  # told, and the failure is raised for the caller to report.
  # Returns the moved ids and how many ids the chunks held between them.
  defp move_chunks(chunks, deployment_group, user) do
    {moved, selected, failure} =
      Enum.reduce_while(chunks, {[], 0, nil}, fn chunk, {moved, selected, nil} ->
        try do
          {:cont, {[move_chunk(chunk, deployment_group, user) | moved], selected + length(chunk), nil}}
        rescue
          error -> {:halt, {moved, selected, {error, __STACKTRACE__}}}
        end
      end)

    moved = moved |> Enum.reverse() |> List.flatten()

    :ok = announce_moved(moved, deployment_group)

    case failure do
      nil -> {moved, selected}
      {error, stacktrace} -> reraise error, stacktrace
    end
  end

  defp move_chunk(chunk, deployment_group, user) do
    {:ok, moved} =
      Repo.transact(fn ->
        {_count, moved} =
          Device
          |> join(:inner, [d], o in assoc(d, :org), as: :org)
          |> join(:inner, [org: o], u in assoc(o, :users), as: :users)
          |> where([users: users], users.id == ^user.id)
          |> Repo.exclude_deleted()
          |> where([d], d.id in ^chunk)
          |> where(
            [d],
            d.firmware_metadata["platform"] == ^deployment_group.current_release.firmware.platform
          )
          |> where(
            [d],
            d.firmware_metadata["architecture"] ==
              ^deployment_group.current_release.firmware.architecture
          )
          |> select([d], d.id)
          |> Repo.update_all([set: [deployment_id: deployment_group.id]], timeout: to_timeout(minute: 2))

        _ = ManagedDeployments.trigger_delta_generation_for_deployment_group(deployment_group)

        {:ok, moved}
      end)

    moved
  end

  defp announce_moved([], _deployment_group), do: :ok

  defp announce_moved(moved_device_ids, deployment_group) do
    :ok = notify_deployment_assigned(moved_device_ids, deployment_group.id)

    # let the orchestrator know that some devices have been added to the deployment group
    DeploymentOrchestratorEvents.bulk_devices_added(deployment_group)
  end

  # How many moved devices hear about their new group at a time, and how long
  # to wait between them. A device that hears `deployment_updated` looks up its
  # group's archive, so telling a whole fleet at once is that many queries at
  # once from the device nodes. These keep it to about 10,000 a second.
  #
  # The pauses come between batches, not after the last, so announcing a move
  # takes at least (batches - 1) x 100ms, plus the time to send each batch:
  #
  #   10,000 devices    10 batches   0.9s
  #   190,000 devices  190 batches   18.9s
  #   250,000 devices  250 batches   24.9s
  #
  # A device keeps its old group until its batch is sent.
  @notify_batch_size 1_000
  @notify_batch_pause to_timeout(millisecond: 100)

  # The rows are already committed, so this is only news for the devices'
  # channels. A device that misses it reads its group again when it reconnects,
  # so it's sent off the caller's process rather than holding it up for the
  # seconds a large move takes to announce.
  defp notify_deployment_assigned(device_ids, deployment_id) do
    {:ok, _pid} =
      Task.Supervisor.start_child(Tasks, fn ->
        device_ids
        |> Enum.chunk_every(@notify_batch_size)
        |> Enum.intersperse(:pause)
        |> Enum.each(fn
          :pause ->
            Process.sleep(@notify_batch_pause)

          batch ->
            Enum.each(batch, &DeviceEvents.deployment_assigned(%Device{id: &1, deployment_id: deployment_id}))
        end)
      end)

    :ok
  end

  @doc """
  Move the devices a query selects into a deployment group, such as the query
  from `ManagedDeployments.matched_devices_query/2`.

  Works like `move_many_to_deployment_group/3` given ids, 5,000 devices to a
  transaction, but reads the ids from the query a chunk
  at a time instead of being handed every one. A move of a whole fleet then
  holds one chunk of ids at a time, rather than loading them all to send them
  straight back.

  `ignored` counts devices the query selected that weren't moved, for instance
  because something else moved them first.

  move_matched_to_deployment_group(query, deployment_group, user)
  > %{updated: 3, ignored: 0}
  """
  @spec move_matched_to_deployment_group(Ecto.Query.t(), DeploymentGroup.t(), User.t()) ::
          %{updated: non_neg_integer(), ignored: non_neg_integer()}
  def move_matched_to_deployment_group(%Ecto.Query{} = devices_query, %DeploymentGroup{id: deployment_id}, user) do
    deployment_group = get_deployment_group_for_move!(deployment_id, user)

    {moved_device_ids, selected} =
      devices_query
      |> device_id_pages(@move_chunk_size)
      |> move_chunks(deployment_group, user)

    devices_updated_count = length(moved_device_ids)

    %{updated: devices_updated_count, ignored: selected - devices_updated_count}
  end

  # The query's ids in order, a page at a time, each page starting after the
  # last id of the one before. Paging by id rather than by offset means a page
  # never skips or repeats a device as earlier pages are moved.
  defp device_id_pages(devices_query, page_size) do
    Stream.unfold(0, fn
      :done ->
        nil

      after_id ->
        page =
          devices_query
          |> exclude(:select)
          |> exclude(:order_by)
          |> where([d], d.id > ^after_id)
          |> order_by([d], asc: d.id)
          |> limit(^page_size)
          |> select([d], d.id)
          |> Repo.all()

        case page do
          [] -> nil
          page when length(page) < page_size -> {page, :done}
          page -> {page, List.last(page)}
        end
    end)
  end

  defp get_deployment_group_for_move!(deployment_id, user) do
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
