defmodule NervesHub.Devices.BulkActions do
  import Ecto.Query

  alias NervesHub.Accounts.Scope
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

  require Logger

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

  @spec tag_devices([Device.t()], User.t(), list(String.t())) :: %{
          ok: [Device.t()],
          error: [{Ecto.Multi.name(), any()}]
        }
  def tag_devices(devices, user, tags) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :tag_device, [&1, user, tags]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  @doc """
  Remove multiple devices from their deployment groups.

  Returns `{:ok, count}` with the number of devices updated.
  """
  @spec remove_many_from_deployment_group(Scope.t(), [non_neg_integer()]) :: {:ok, non_neg_integer()}
  def remove_many_from_deployment_group(%Scope{product: product}, device_ids) when is_list(device_ids) do
    {count, _} =
      Device
      |> Repo.exclude_deleted()
      |> where([d], d.id in ^device_ids)
      |> where([d], d.product_id == ^product.id)
      |> where([d], not is_nil(d.deployment_id))
      |> Repo.update_all(set: [deployment_id: nil])

    Enum.each(device_ids, &DeviceEvents.updated(%Device{id: &1}))

    {:ok, count}
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
          Scope.t(),
          [non_neg_integer()],
          DeploymentGroup.t() | non_neg_integer()
        ) ::
          {:ok, %{updated: non_neg_integer(), ignored: non_neg_integer()}}
  def move_many_to_deployment_group(%Scope{} = scope, device_ids, %DeploymentGroup{id: deployment_id}) do
    move_many_to_deployment_group(scope, device_ids, deployment_id)
  end

  def move_many_to_deployment_group(%Scope{} = scope, device_ids, deployment_id) when is_number(deployment_id) do
    deployment_group =
      DeploymentGroup
      |> from(as: :deployment_group)
      |> join(:inner, [deployment_group: dg], o in assoc(dg, :org), as: :org)
      |> join(:inner, [org: o], u in assoc(o, :users), as: :users)
      |> ManagedDeployments.join_current_release()
      |> join(:inner, [current_release: cr], f in assoc(cr, :firmware), as: :firmware)
      |> where([deployment_group: dg], dg.id == ^deployment_id)
      |> where([users: users], users.id == ^scope.user.id)
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
          |> where([users: users], users.id == ^scope.user.id)
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

    {:ok, %{updated: devices_updated_count, ignored: length(device_ids) - devices_updated_count}}
  end

  @spec move_many(Scope.t(), [Device.t()], Product.t()) :: %{
          ok: [Device.t()],
          error: [{Ecto.Multi.name(), any()}]
        }
  def move_many(%Scope{user: user}, devices, product) do
    product = Repo.preload(product, :org)

    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :move, [&1, product, user]))
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
    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :enable_updates, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  @spec disable_updates_for_devices([Device.t()], User.t()) :: %{
          ok: [Device.t()],
          error: [{Ecto.Multi.name(), any()}]
        }
  def disable_updates_for_devices(devices, user) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :disable_updates, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def clear_penalty_box_for_devices(devices, user) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, Devices, :clear_penalty_box, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def async_remove_many_from_deployment_group(devices_query, callback_pid) do
    Task.Supervisor.start_child(Tasks, fn ->
      devices_query
      |> stream_processing(fn device ->
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
      |> case do
        {:ok, %{ok: successful_count, error: 0}} ->
          send_async_msg(callback_pid, "All device(s) (#{successful_count}) removed from their deployment group.")

        {:ok, %{ok: 0, error: _}} ->
          send_async_msg(callback_pid, "No devices were successfully removed from their deployment group.", :error)

        {:ok, %{ok: successful_count, error: unsuccessful_count}} ->
          send_async_msg(
            callback_pid,
            "#{successful_count} devices were successfully from their deployment group, and #{unsuccessful_count} devices had errors and couldn't be removed",
            :notice
          )
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:ok, _, _} -> :ok
    end
  end

  def async_move_many_to_deployment_group(devices_query, deployment_id, scope, callback_pid) do
    deployment_group =
      DeploymentGroup
      |> from(as: :deployment_group)
      |> join(:inner, [deployment_group: dg], o in assoc(dg, :org), as: :org)
      |> join(:inner, [org: o], u in assoc(o, :users), as: :users)
      |> ManagedDeployments.join_current_release()
      |> join(:inner, [current_release: cr], f in assoc(cr, :firmware), as: :firmware)
      |> where([deployment_group: dg], dg.id == ^deployment_id)
      |> where([users: users], users.id == ^scope.user.id)
      |> preload([firmware: f, current_release: cr],
        current_release: {cr, firmware: f}
      )
      |> Repo.one!()

    Task.Supervisor.start_child(Tasks, fn ->
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
      |> case do
        {:ok, %{ok: _, error: 0}} ->
          send(
            callback_pid,
            {:async_update_complete, :info, "All selected devices successfully assigned to #{deployment_group.name}"}
          )

        {:ok, %{ok: 0, error: _}} ->
          send(
            callback_pid,
            {:async_update_complete, :error, "No devices were successfully assigned to #{deployment_group.name}"}
          )

        {:ok, %{ok: successful_count, error: unsuccessful_count}} ->
          send(
            callback_pid,
            {:async_update_complete, :notice,
             "#{successful_count} devices were successfully assigned to #{deployment_group.name}, and #{unsuccessful_count} devices had errors and couldn't be assigned"}
          )
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:ok, _, _} -> :ok
    end
  end

  def async_move_many(devices_query, target_product, user, callback_pid) do
    Task.Supervisor.start_child(Tasks, fn ->
      devices_query
      |> stream_processing({:move, [target_product, user]})
      |> case do
        {:ok, %{ok: _, error: 0}} ->
          send_async_msg(callback_pid, "All selected devices successfully moved to #{target_product.name}")

        {:ok, %{ok: 0, error: _}} ->
          send_async_msg(callback_pid, "No devices were successfully moved to #{target_product.name}", :error)

        {:ok, %{ok: successful_count, error: unsuccessful_count}} ->
          send_async_msg(
            callback_pid,
            "#{successful_count} devices were successfully moved to #{target_product.name}, and #{unsuccessful_count} devices had errors and couldn't be moved",
            :notice
          )
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:ok, _, _} -> :ok
    end
  end

  def async_disable_updates_for_devices(devices_query, user, callback_pid) do
    Task.Supervisor.start_child(Tasks, fn ->
      devices_query
      |> stream_processing({:disable_updates, [user]})
      |> case do
        {:ok, res} ->
          send_async_msg(callback_pid, "Disabled updates for #{res.ok} selected device(s).")
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:ok, _, _} -> :ok
    end
  end

  def async_tag_devices(devices_query, user, tags, callback_pid) do
    Task.Supervisor.start_child(Tasks, fn ->
      devices_query
      |> stream_processing({:tag_device, [user, tags]})
      |> case do
        {:ok, %{ok: successful_count, error: 0}} ->
          send_async_msg(callback_pid, "All selected devices (#{successful_count}) tagged successfully.")

        {:ok, %{ok: 0, error: unsuccessful_count}} ->
          send_async_msg(
            callback_pid,
            "All selected devices (#{unsuccessful_count}) failed updating with new tags.",
            :error
          )

        {:ok, %{ok: successful_count, error: unsuccessful_count}} ->
          send_async_msg(
            callback_pid,
            "#{successful_count} devices were successfully tagged and #{unsuccessful_count} devices had errors.",
            :notice
          )
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:ok, _, _} -> :ok
    end
  end

  def async_enable_updates_for_devices(devices_query, user, callback_pid) do
    Task.Supervisor.start_child(Tasks, fn ->
      devices_query
      |> stream_processing({:enable_updates, [user]})
      |> case do
        {:ok, res} ->
          send_async_msg(callback_pid, "Enabled updates for #{res.ok} selected device(s).")
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:ok, _, _} -> :ok
    end
  end

  def async_clear_penalty_box_for_devices(devices_query, user, callback_pid) do
    Task.Supervisor.start_child(Tasks, fn ->
      devices_query
      |> stream_processing({:clear_penalty_box, [user]})
      |> case do
        {:ok, res} ->
          send_async_msg(callback_pid, "#{res.ok} selected device(s) cleared from the penalty box.")
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:ok, _, _} -> :ok
    end
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
  end

  defp send_async_msg(callback_pid, message, key \\ :info) do
    send(callback_pid, {:async_update_complete, key, message})
  end
end
