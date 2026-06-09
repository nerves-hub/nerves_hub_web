defmodule NervesHub.Devices.BulkActions do
  import Ecto.Query

  alias NervesHub.Accounts.User
  alias NervesHub.Certificate
  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.BulkImport
  alias NervesHub.Devices.Device
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
             {:ok, _db_cert} <- Devices.create_device_certificate(device, otp_cert) do
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
    stream_processing(devices_query, {:tag_device, [user, tags]})
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
    stream_processing(devices_query, {:move, [target_product, user]})
  end

  @spec enable_updates_for_devices([Device.t()] | Ecto.Query.t(), User.t()) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def enable_updates_for_devices(devices, user) when is_list(devices) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :enable_updates, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def enable_updates_for_devices(%Ecto.Query{} = devices_query, user) do
    stream_processing(devices_query, {:enable_updates, [user]})
  end

  @spec disable_updates_for_devices([Device.t()] | Ecto.Query.t(), User.t()) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def disable_updates_for_devices(devices, user) when is_list(devices) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :disable_updates, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def disable_updates_for_devices(%Ecto.Query{} = devices_query, user) do
    stream_processing(devices_query, {:disable_updates, [user]})
  end

  @spec clear_penalty_box_for_devices([Device.t()] | Ecto.Query.t(), User.t()) ::
          %{ok: [Device.t()], error: [{Ecto.Multi.name(), any()}]}
          | %{ok: non_neg_integer(), error: non_neg_integer()}
  def clear_penalty_box_for_devices(devices, user) when is_list(devices) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :clear_penalty_box, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def clear_penalty_box_for_devices(%Ecto.Query{} = devices_query, user) do
    stream_processing(devices_query, {:clear_penalty_box, [user]})
  end

  defp stream_processing(devices_query, fun, opts \\ []) do
    stream = Repo.stream(devices_query)

    Repo.transact(
      fn ->
        stream
        |> Stream.map(fn device ->
          case fun do
            {fun_name, args} ->
              apply(NervesHub.Devices, fun_name, [device | args])

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
