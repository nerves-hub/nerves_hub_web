defmodule NervesHub.ManagedDeployments do
  import Ecto.Query

  require Logger

  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Deployments.InflightDeploymentCheck
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.Distributed.Orchestrator, as: DistributedOrchestrator
  alias NervesHub.ManagedDeployments.Filtering
  alias NervesHub.ManagedDeployments.InflightDeploymentCheck
  alias NervesHub.Products.Product
  alias NervesHub.Workers.FirmwareDeltaBuilder

  alias NervesHub.Repo

  alias Ecto.Changeset

  @spec all() :: [DeploymentGroup.t()]
  def all() do
    Repo.all(DeploymentGroup)
  end

  @spec should_run_orchestrator() :: [DeploymentGroup.t()]
  def should_run_orchestrator() do
    DeploymentGroup
    |> where(is_active: true)
    |> Repo.all()
  end

  @spec filter(Product.t(), map()) :: {[Product.t()], Flop.Meta.t()}
  def filter(product, opts \\ %{}) do
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) end)
    pagination = Map.get(opts, :pagination, %{})
    sorting = Map.get(opts, :sort, {:asc, :name})

    filters = Map.get(opts, :filters, %{})

    flop = %Flop{
      page: pagination.page,
      page_size: pagination.page_size
    }

    subquery =
      Device
      |> select([d], %{
        deployment_id: d.deployment_id,
        device_count: count()
      })
      |> Repo.exclude_deleted()
      |> group_by([d], d.deployment_id)

    DeploymentGroup
    |> join(:left, [d], dev in subquery(subquery), on: dev.deployment_id == d.id)
    |> join(:left, [d], f in assoc(d, :firmware))
    |> where([d], d.product_id == ^product.id)
    |> Filtering.build_filters(filters)
    |> sort_deployment_groups(sorting)
    |> preload([_d, _dev, f], firmware: f)
    |> select_merge([_f, dev], %{device_count: dev.device_count})
    |> Flop.run(flop)
  end

  defp sort_deployment_groups(query, {direction, :platform}) do
    order_by(query, [_d, _dev, f], {^direction, f.platform})
  end

  defp sort_deployment_groups(query, {direction, :architecture}) do
    order_by(query, [_d, _dev, f], {^direction, f.architecture})
  end

  defp sort_deployment_groups(query, {direction, :device_count}) do
    order_by(query, [_d, dev], {^direction, dev.device_count})
  end

  defp sort_deployment_groups(query, {direction, :firmware_version}) do
    order_by(query, [_d, _dev, f], {^direction, f.version})
  end

  defp sort_deployment_groups(query, sort), do: order_by(query, ^sort)

  @spec get_deployment_groups_by_product(Product.t()) :: [DeploymentGroup.t()]
  def get_deployment_groups_by_product(%Product{id: product_id}) do
    DeploymentGroup
    |> join(:inner, [d], f in assoc(d, :firmware), on: f.product_id == ^product_id)
    |> preload([_d, f], firmware: f, firmware: :product)
    |> order_by(:name)
    |> Repo.all()
  end

  @spec get_device_counts_by_product(Product.t()) :: %{integer() => integer()}
  def get_device_counts_by_product(%Product{id: product_id}) do
    Device
    |> select([d], {d.deployment_id, count(d.id)})
    |> where([d], d.product_id == ^product_id)
    |> group_by([d], d.deployment_id)
    |> Repo.exclude_deleted()
    |> Repo.all()
    |> Map.new()
  end

  @spec get_device_count(DeploymentGroup.t()) :: term() | nil
  def get_device_count(%DeploymentGroup{id: id}) do
    Device
    |> where([d], d.deployment_id == ^id)
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  @spec get_deployment_groups_by_firmware(integer()) :: [DeploymentGroup.t()]
  def get_deployment_groups_by_firmware(firmware_id) do
    DeploymentGroup
    |> where([d], d.firmware_id == ^firmware_id)
    |> Repo.all()
  end

  @spec get(integer()) :: {:ok, DeploymentGroup.t()} | {:error, :not_found}
  def get(id) when is_integer(id) do
    case Repo.get(DeploymentGroup, id) do
      nil ->
        {:error, :not_found}

      deployment_group ->
        {:ok, deployment_group}
    end
  end

  @spec get_deployment_group_for_device(Device.t()) ::
          {:ok, DeploymentGroup.t()} | {:error, :not_found}
  def get_deployment_group_for_device(%Device{deployment_id: deployment_id}) do
    DeploymentGroup
    |> where([d], d.id == ^deployment_id)
    |> join(:left, [d], f in assoc(d, :firmware))
    |> preload([d, f], firmware: f)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      deployment_group ->
        {:ok, deployment_group}
    end
  end

  @spec get_deployment_group(Product.t(), String.t()) ::
          {:ok, DeploymentGroup.t()} | {:error, :not_found}
  def get_deployment_group(%Product{id: product_id}, deployment_id) do
    from(
      d in DeploymentGroup,
      where: d.id == ^deployment_id,
      join: f in assoc(d, :firmware),
      where: f.product_id == ^product_id,
      preload: [{:firmware, :product}]
    )
    |> DeploymentGroup.with_firmware()
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      deployment_group ->
        {:ok, deployment_group}
    end
  end

  def get_deployment_group(%DeploymentGroup{id: id}), do: get_deployment_group(id)

  def get_deployment_group(deployment_id) do
    DeploymentGroup
    |> where([d], d.id == ^deployment_id)
    |> join(:left, [d], f in assoc(d, :firmware), as: :firmware)
    |> preload([firmware: f], firmware: f)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      deployment ->
        {:ok, deployment}
    end
  end

  @spec get_by_product_and_name!(Product.t(), String.t(), boolean()) :: DeploymentGroup.t()
  def get_by_product_and_name!(product, name, with_device_count \\ false)

  def get_by_product_and_name!(product, name, true) do
    subquery =
      Device
      |> select([d], %{
        deployment_id: d.deployment_id,
        device_count: count()
      })
      |> Repo.exclude_deleted()
      |> group_by([d], d.deployment_id)

    get_by_product_and_name_query(product, name)
    |> join(:left, [d], dev in subquery(subquery), on: dev.deployment_id == d.id, as: :devices)
    |> select_merge([_f, devices: devices], %{device_count: devices.device_count})
    |> Repo.one!()
  end

  def get_by_product_and_name!(product, name, false) do
    get_by_product_and_name_query(product, name)
    |> Repo.one!()
  end

  @spec get_by_product_and_platform(Product.t(), binary()) :: [DeploymentGroup.t()]
  def get_by_product_and_platform(product, platform) do
    DeploymentGroup
    |> where(product_id: ^product.id)
    |> join(:left, [d], f in assoc(d, :firmware))
    |> where([_d, f], f.platform == ^platform)
    |> preload([_d, f], firmware: f)
    |> order_by([d], asc: d.name)
    |> Repo.all()
  end

  @spec get_deployment_group_by_name(Product.t(), String.t()) ::
          {:ok, DeploymentGroup.t()} | {:error, :not_found}
  def get_deployment_group_by_name(product, name) do
    get_by_product_and_name_query(product, name)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      deployment_group ->
        {:ok, deployment_group}
    end
  end

  defp get_by_product_and_name_query(%Product{id: product_id}, name) do
    DeploymentGroup
    |> where(name: ^name)
    |> where(product_id: ^product_id)
    |> join(:left, [d], f in assoc(d, :firmware))
    |> join(:left, [d], a in assoc(d, :archive))
    |> join(:left, [d], p in assoc(d, :product))
    |> preload([d, f, a, p], firmware: f, archive: a, product: p)
  end

  @spec delete_deployment_group(DeploymentGroup.t()) ::
          {:ok, DeploymentGroup.t()} | {:error, :not_found}
  def delete_deployment_group(%DeploymentGroup{id: deployment_id}) do
    DeploymentGroup
    |> Repo.get!(deployment_id)
    |> Repo.delete()
    |> case do
      {:error, _changeset} ->
        {:error, :not_found}

      {:ok, deployment_group} ->
        _ = deployment_deleted_event(deployment_group)

        {:ok, deployment_group}
    end
  end

  @doc """
  Update a deployment

  - Records audit logs depending on changes
  """
  @spec update_deployment_group(DeploymentGroup.t(), map) ::
          {:ok, DeploymentGroup.t()} | {:error, Changeset.t()}
  def update_deployment_group(deployment_group, params) do
    result =
      Repo.transaction(fn ->
        device_count =
          Device
          |> select([d], count(d))
          |> where([d], d.deployment_id == ^deployment_group.id)
          |> Repo.one()

        changeset =
          deployment_group
          |> DeploymentGroup.with_firmware()
          |> DeploymentGroup.changeset(params)
          |> Ecto.Changeset.put_change(:total_updating_devices, device_count)

        case Repo.update(changeset) do
          {:ok, deployment_group} ->
            deployment_group = Repo.preload(deployment_group, [:firmware], force: true)

            audit_changes!(deployment_group, changeset)

            {deployment_group, changeset}

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, {deployment_group, changeset}} ->
        _ = maybe_trigger_delta_generation(deployment_group, changeset)
        :ok = broadcast(deployment_group, "deployments/update")

        if Map.has_key?(changeset.changes, :is_active) do
          if deployment_group.is_active do
            deployment_activated_event(deployment_group)
          else
            deployment_deactivated_event(deployment_group)
          end
        end

        if Map.has_key?(changeset.changes, :orchestrator_strategy) do
          if deployment_group.orchestrator_strategy == :distributed do
            start_deployments_distributed_orchestrator_event(deployment_group)
          else
            shutdown_deployments_distributed_orchestrator_event(deployment_group)
          end
        end

        {:ok, deployment_group}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp audit_changes!(deployment_group, changeset) do
    Enum.each(changeset.changes, fn
      {:archive_id, archive_id} ->
        # Trigger the new archive to get downloaded by devices
        payload = %{archive_id: archive_id}
        _ = broadcast(deployment_group, "archives/updated", payload)

        DeploymentGroupTemplates.audit_deployment_group_change(
          deployment_group,
          "has a new archive"
        )

      {:conditions, _new_conditions} ->
        DeploymentGroupTemplates.audit_deployment_group_change(
          deployment_group,
          "conditions changed"
        )

      {:is_active, is_active} when is_active != true ->
        DeploymentGroupTemplates.audit_deployment_group_change(deployment_group, "is inactive")

      _ ->
        :ignore
    end)
  end

  defp maybe_trigger_delta_generation(deployment_group, changeset) do
    # Firmware changed on active deployment
    if deployment_group.is_active and Map.has_key?(changeset.changes, :firmware_id) do
      deployment_group = Repo.preload(deployment_group, :product, force: true)

      if deployment_group.product.delta_updatable do
        trigger_delta_generation_for_deployment_group(deployment_group)
      end
    end
  end

  defp trigger_delta_generation_for_deployment_group(deployment_group) do
    NervesHub.Devices.get_device_firmware_for_delta_generation_by_deployment_group(
      deployment_group.id
    )
    |> Enum.uniq()
    |> Enum.each(fn {source_id, target_id} ->
      FirmwareDeltaBuilder.start(source_id, target_id)
    end)
  end

  @doc """
  Delete any matching inflight deployment checks for devices
  """
  @spec delete_inflight_checks(DeploymentGroup.t()) :: :ok
  def delete_inflight_checks(deployment_group) do
    _ =
      InflightDeploymentCheck
      |> where([idc], idc.deployment_id == ^deployment_group.id)
      |> Repo.delete_all()

    :ok
  end

  @spec new_deployment_group() :: Changeset.t()
  def new_deployment_group() do
    Ecto.Changeset.change(%DeploymentGroup{})
  end

  @spec create_deployment_group(map()) :: {:ok, DeploymentGroup.t()} | {:error, Changeset.t()}
  def create_deployment_group(params) do
    changeset = DeploymentGroup.creation_changeset(%DeploymentGroup{}, params)

    case Repo.insert(changeset) do
      {:ok, deployment_group} ->
        deployment_created_event(deployment_group)

        {:ok, deployment_group}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec broadcast(DeploymentGroup.t() | atom(), String.t(), map()) :: :ok | {:error, term()}
  def broadcast(deployment_group, event, payload \\ %{})

  def broadcast(:none, event, payload) do
    Phoenix.Channel.Server.broadcast(
      NervesHub.PubSub,
      "deployment:none",
      event,
      payload
    )
  end

  def broadcast(%DeploymentGroup{id: id}, event, payload) do
    Phoenix.Channel.Server.broadcast(
      NervesHub.PubSub,
      "deployment:#{id}",
      event,
      payload
    )
  end

  @doc """
  Find all potential devices for a deployment

  Based on the product, firmware platform, firmware architecture, and device tags
  """
  @spec estimate_devices_matched_by_conditions(integer(), String.t(), map()) :: integer()
  def estimate_devices_matched_by_conditions(product_id, platform, conditions) do
    Device
    |> where([dev], dev.product_id == ^product_id)
    |> where([dev], fragment("d0.firmware_metadata ->> 'platform'") == ^platform)
    |> where([dev], fragment("?::jsonb->'tags' <@ to_jsonb(?::text[])", ^conditions, dev.tags))
    |> Repo.all()
    |> Enum.count(&version_match?(&1, %{conditions: conditions}))
  end

  # Check that a device version matches for a deployment's conditions
  # A deployment not having a version condition returns true
  defp version_match?(_device, %{conditions: %{"version" => ""}}), do: true

  defp version_match?(device, %{conditions: %{"version" => version}}) when not is_nil(version) do
    Version.match?(device.firmware_metadata.version, version)
  end

  defp version_match?(_device, _deployment_group), do: true

  @spec verify_deployment_group_membership(Device.t()) :: Device.t()
  def verify_deployment_group_membership(
        %Device{deployment_id: deployment_id, firmware_metadata: %{version: device_version}} =
          device
      )
      when not is_nil(deployment_id) do
    {:ok, deployment_group} = get_deployment_group_for_device(device)

    bad_version =
      if deployment_group.conditions["version"] != "" do
        !Version.match?(device_version, deployment_group.conditions["version"])
      else
        false
      end

    bad_platform = device.firmware_metadata.platform != deployment_group.firmware.platform

    bad_architecture =
      device.firmware_metadata.architecture != deployment_group.firmware.architecture

    reason =
      cond do
        bad_version ->
          "mismatched version"

        bad_platform ->
          "mismatched platform"

        bad_architecture ->
          "mismatched architecture"

        true ->
          nil
      end

    if reason do
      device =
        device
        |> Ecto.Changeset.change(%{deployment_id: nil})
        |> Repo.update!()

      DeploymentGroupTemplates.audit_deployment_mismatch(device, deployment_group, reason)

      device
    else
      device
    end
  end

  def verify_deployment_group_membership(device), do: device

  @doc """
  If the device is missing a deployment group, find a matching deployment group

  Do nothing if a deployment group is already set
  """
  @spec set_deployment_group(Device.t()) :: Device.t()
  def set_deployment_group(%{deployment_id: nil} = device) do
    case matching_deployment_groups(device, [true]) do
      [] ->
        set_deployment_group_telemetry(:none_found, device)

        %{device | deployment_group: nil}

      [deployment] ->
        set_deployment_group_telemetry(:one_found, device, deployment)

        DeviceTemplates.audit_set_deployment(device, deployment, :one_found)

        Devices.update_deployment_group(device, deployment)

      [deployment | _] ->
        set_deployment_group_telemetry(:multiple_found, device, deployment)

        DeviceTemplates.audit_set_deployment(device, deployment, :multiple_found)

        Devices.update_deployment_group(device, deployment)
    end
  end

  def set_deployment_group(device) do
    preload_with_firmware_and_archive(device)
  end

  defp set_deployment_group_telemetry(result, device, deployment_group \\ nil) do
    metadata = %{device: device}

    metadata =
      if deployment_group do
        Map.put(metadata, :deployment_group, deployment_group)
      else
        metadata
      end

    :telemetry.execute(
      [:nerves_hub, :managed_deployments, :set_deployment_group, result],
      %{count: 1},
      metadata
    )
  end

  @spec preload_firmware_and_archive(DeploymentGroup.t()) :: DeploymentGroup.t()
  def preload_firmware_and_archive(deployment_group) do
    %DeploymentGroup{} = Repo.preload(deployment_group, [:archive, :firmware])
  end

  @spec preload_with_firmware_and_archive(Device.t(), boolean()) :: Device.t()
  def preload_with_firmware_and_archive(device, force \\ false) do
    %Device{} = Repo.preload(device, [deployment_group: [:archive, :firmware]], force: force)
  end

  @doc """
  Find all potential deployment groups for a device

  Based on the product, firmware platform, firmware architecture, and device tags
  """
  @spec matching_deployment_groups(Device.t(), [boolean()]) :: [DeploymentGroup.t()]
  def matching_deployment_groups(device, active \\ [true, false])
  def matching_deployment_groups(%Device{firmware_metadata: nil}, _active), do: []

  def matching_deployment_groups(device, active) do
    DeploymentGroup
    |> join(:inner, [d], assoc(d, :firmware), as: :firmware)
    |> preload([_, firmware: f], firmware: f)
    |> where([d], d.product_id == ^device.product_id)
    |> where([d], d.is_active in ^active)
    |> ignore_same_deployment_group(device)
    |> where([d, firmware: f], f.platform == ^device.firmware_metadata.platform)
    |> where([d, firmware: f], f.architecture == ^device.firmware_metadata.architecture)
    |> where([d], fragment("?->'tags' <@ to_jsonb(?::text[])", d.conditions, ^device.tags))
    |> Repo.all()
    |> Enum.filter(&version_match?(device, &1))
    |> Enum.sort_by(
      &{&1.firmware.version, &1.id},
      fn {a_vsn, a_id}, {b_vsn, b_id} ->
        case Version.compare(a_vsn, b_vsn) do
          :lt -> false
          :eq -> a_id <= b_id
          :gt -> true
        end
      end
    )
  end

  defp ignore_same_deployment_group(query, %{deployment_id: nil}), do: query

  defp ignore_same_deployment_group(query, %{deployment_id: deployment_id}) do
    where(query, [d], d.id != ^deployment_id)
  end

  @doc """
  Find all eligible deployment groups for a device, based on the firmware platform,
  firmware architecture, and product.

  This is purposefully less-strict then Deployments.matching_deployment_groups/2
  and should only be used when a human is choosing the deployment for a device.
  """
  @spec eligible_deployment_groups(Device.t()) :: [DeploymentGroup.t()]
  def eligible_deployment_groups(%Device{firmware_metadata: nil}), do: []

  def eligible_deployment_groups(device) do
    DeploymentGroup
    |> join(:inner, [d], assoc(d, :firmware), as: :firmware)
    |> preload([_, firmware: f], firmware: f)
    |> where([d, _], d.product_id == ^device.product_id)
    |> where([d, firmware: f], f.platform == ^device.firmware_metadata.platform)
    |> where([d, firmware: f], f.architecture == ^device.firmware_metadata.architecture)
    |> order_by([d], asc: d.name)
    |> Repo.all()
  end

  def deployment_created_event(deployment_group) do
    _ = DistributedOrchestrator.start_orchestrator(deployment_group)

    :ok
  end

  def start_deployments_distributed_orchestrator_event(deployment_group) do
    _ = DistributedOrchestrator.start_orchestrator(deployment_group)

    :ok
  end

  def shutdown_deployments_distributed_orchestrator_event(deployment) do
    _ =
      Phoenix.Channel.Server.broadcast(
        NervesHub.PubSub,
        "orchestrator:deployment:#{deployment.id}",
        "deactivated",
        %{}
      )

    :ok
  end

  def deployment_activated_event(deployment_group) do
    _ = DistributedOrchestrator.start_orchestrator(deployment_group)

    :ok
  end

  def deployment_deactivated_event(deployment_group) do
    _ =
      Phoenix.Channel.Server.broadcast(
        NervesHub.PubSub,
        "orchestrator:deployment:#{deployment_group.id}",
        "deactivated",
        %{}
      )

    :ok
  end

  def deployment_deleted_event(deployment_group) do
    _ = broadcast(deployment_group, "deleted")

    :ok
  end

  @doc """
  Count the number of devices that match the deployment group's conditions. Takes into account deployment
  groups with no tags and/or no version.

  When passing `in_deployment: true`, only devices from the deployment group will be considered.
  Passing `false` for the option will only consider devices outside of the deployment group.
  """
  @spec matched_devices_count(DeploymentGroup.t(), in_deployment: boolean()) :: non_neg_integer()
  def matched_devices_count(deployment_group, in_deployment: in_deployment) do
    deployment_group = Repo.preload(deployment_group, [:firmware])
    query = matched_devices_base_query(deployment_group, in_deployment)

    do_matched_devices(deployment_group, query, :count)
  end

  @doc """
  Identical to matched_devices_count/2, but a list of device ids are returned instead.
  """
  @spec matched_device_ids(DeploymentGroup.t(), in_deployment: boolean()) :: [non_neg_integer()]
  def matched_device_ids(deployment_group, in_deployment: in_deployment) do
    deployment_group = Repo.preload(deployment_group, [:firmware])
    query = matched_devices_base_query(deployment_group, in_deployment)

    do_matched_devices(deployment_group, query, :collect_ids)
  end

  defp matched_devices_base_query(deployment_group, in_deployment) do
    base_query =
      Device
      |> Repo.exclude_deleted()
      |> where([d], d.product_id == ^deployment_group.product_id)
      |> where([d], d.firmware_metadata["platform"] == ^deployment_group.firmware.platform)
      |> where(
        [d],
        d.firmware_metadata["architecture"] == ^deployment_group.firmware.architecture
      )

    if in_deployment do
      where(base_query, [d], d.deployment_id == ^deployment_group.id)
    else
      where(base_query, [d], is_nil(d.deployment_id))
    end
  end

  # no tags, but version
  defp do_matched_devices(
         %DeploymentGroup{conditions: %{"tags" => [], "version" => version}},
         query,
         work_type
       )
       when version != "" do
    case work_type do
      :count ->
        query
        |> select([d], d.firmware_metadata["version"])
        |> Repo.all()
        |> Enum.count(&Version.match?(&1, version))

      :collect_ids ->
        query
        |> select([d], %{id: d.id, version: d.firmware_metadata["version"]})
        |> Repo.all()
        |> Enum.filter(&Version.match?(&1.version, version))
        |> Enum.map(& &1.id)
    end
  end

  # tags but no version
  defp do_matched_devices(
         %DeploymentGroup{conditions: %{"tags" => tags, "version" => ""}},
         query,
         work_type
       ) do
    query = where(query, [d], fragment("?::text[] && tags::text[]", ^tags))

    case work_type do
      :count ->
        Repo.aggregate(query, :count)

      :collect_ids ->
        query
        |> select([d], d.id)
        |> Repo.all()
    end
  end

  # version and tags
  defp do_matched_devices(
         %DeploymentGroup{conditions: %{"tags" => tags, "version" => version}},
         query,
         work_type
       ) do
    query = where(query, [d], fragment("?::text[] && tags::text[]", ^tags))

    case work_type do
      :count ->
        query
        |> select([d], d.firmware_metadata["version"])
        |> Repo.all()
        |> Enum.count(&Version.match?(&1, version))

      :collect_ids ->
        query
        |> select([d], %{id: d.id, version: d.firmware_metadata["version"]})
        |> Repo.all()
        |> Enum.filter(&Version.match?(&1.version, version))
        |> Enum.map(& &1.id)
    end
  end
end
