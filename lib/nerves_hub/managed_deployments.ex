defmodule NervesHub.ManagedDeployments do
  import Ecto.Query

  require Logger

  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Filtering, as: CommonFiltering
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.Distributed.Orchestrator, as: DistributedOrchestrator
  alias NervesHub.Products.Product
  alias Phoenix.Channel.Server, as: PhoenixChannelServer

  alias NervesHub.Repo

  alias Ecto.Changeset

  @spec should_run_orchestrator() :: [DeploymentGroup.t()]
  def should_run_orchestrator() do
    full_deployment_group_query()
    |> where(is_active: true)
    |> Repo.all()
  end

  @spec filter(Product.t(), map()) :: {[DeploymentGroup.t()], Flop.Meta.t()}
  def filter(product, opts \\ %{}) do
    subquery =
      Device
      |> select([d], %{
        deployment_id: d.deployment_id,
        device_count: count()
      })
      |> Repo.exclude_deleted()
      |> group_by([d], d.deployment_id)

    base_query =
      DeploymentGroup
      |> join(:left, [d], dev in subquery(subquery), on: dev.deployment_id == d.id)
      |> join(:left, [d], f in assoc(d, :firmware))
      |> preload([_d, _dev, f], firmware: f)
      |> select_merge([_f, dev], %{device_count: dev.device_count})

    CommonFiltering.filter(
      base_query,
      product,
      opts
    )
  end

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

  @spec get_deployment_group(DeploymentGroup.t() | Device.t() | integer()) ::
          {:ok, DeploymentGroup.t()} | {:error, :not_found}
  def get_deployment_group(%DeploymentGroup{id: id}), do: get_deployment_group(id)

  def get_deployment_group(%Device{deployment_id: deployment_id}), do: get_deployment_group(deployment_id)

  def get_deployment_group(deployment_id) do
    full_deployment_group_query()
    |> where([d], d.id == ^deployment_id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      deployment ->
        {:ok, deployment}
    end
  end

  defp full_deployment_group_query() do
    DeploymentGroup
    |> join(:left, [d], f in assoc(d, :firmware), as: :firmware)
    |> join(:left, [d], p in assoc(d, :product), as: :product)
    |> join(:left, [d], o in assoc(d, :org), as: :org)
    |> preload([d, firmware: f, product: p, org: o], firmware: f, product: p, org: o)
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
        :ok = deployment_deleted_event(deployment_group)

        {:ok, deployment_group}
    end
  end

  @spec toggle_delta_updates(DeploymentGroup.t()) ::
          {:ok, DeploymentGroup.t()} | {:error, Changeset.t()}
  def toggle_delta_updates(deployment_group),
    do: update_deployment_group(deployment_group, %{delta_updatable: !deployment_group.delta_updatable})

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
          |> Repo.preload(:firmware)
          |> DeploymentGroup.update_changeset(params)
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
        :ok = maybe_trigger_delta_generation(deployment_group, changeset)
        :ok = broadcast(deployment_group, "deployments/update")

        if Map.has_key?(changeset.changes, :is_active) do
          if deployment_group.is_active do
            :ok = deployment_activated_event(deployment_group)
          else
            :ok = deployment_deactivated_event(deployment_group)
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

      {:delta_updatable, delta_updatable?} ->
        DeploymentGroupTemplates.audit_deployment_group_change(
          deployment_group,
          "delta updates #{(delta_updatable? && "enabled") || "disabled"}"
        )

      _ ->
        :ignore
    end)
  end

  defp maybe_trigger_delta_generation(
         %{delta_updatable: true} = deployment_group,
         %{changes: %{firmware_id: _}} = _changeset
       ),
       do: trigger_delta_generation_for_deployment_group(deployment_group)

  defp maybe_trigger_delta_generation(deployment_group, %{changes: %{delta_updatable: true}} = _changeset),
    do: trigger_delta_generation_for_deployment_group(deployment_group)

  defp maybe_trigger_delta_generation(_deployment_group, _changeset), do: :ok

  defp trigger_delta_generation_for_deployment_group(deployment_group) do
    NervesHub.Devices.get_device_firmware_for_delta_generation_by_deployment_group(deployment_group.id)
    |> Enum.uniq()
    |> Enum.each(fn {source_id, target_id} ->
      Firmwares.attempt_firmware_delta(source_id, target_id)
    end)
  end

  @spec new_deployment_group() :: Changeset.t()
  def new_deployment_group() do
    Ecto.Changeset.change(%DeploymentGroup{})
  end

  @spec create_deployment_group(map()) :: {:ok, DeploymentGroup.t()} | {:error, Changeset.t()}
  def create_deployment_group(params) do
    changeset = DeploymentGroup.create_changeset(%DeploymentGroup{}, params)

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
    PhoenixChannelServer.broadcast(
      NervesHub.PubSub,
      "deployment:none",
      event,
      payload
    )
  end

  def broadcast(%DeploymentGroup{id: id}, event, payload) do
    PhoenixChannelServer.broadcast(
      NervesHub.PubSub,
      "deployment:#{id}",
      event,
      payload
    )
  end

  # Check that a device version matches for a deployment's conditions
  # A deployment not having a version condition returns true
  defp version_match?(_device, %{conditions: %{"version" => ""}}), do: true

  defp version_match?(device, %{conditions: %{"version" => version}}) when not is_nil(version) do
    Version.match?(device.firmware_metadata.version, version)
  end

  defp version_match?(_device, _deployment_group), do: true

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

  def set_deployment_group(device), do: device

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

  @spec verify_deployment_group_membership(Device.t()) :: Device.t()
  def verify_deployment_group_membership(
        %Device{deployment_id: deployment_id, firmware_metadata: %{version: device_version}} = device
      )
      when not is_nil(deployment_id) do
    deployment_group =
      DeploymentGroup
      |> where([d], d.id == ^deployment_id)
      |> join(:left, [d], f in assoc(d, :firmware))
      |> preload([d, f], firmware: f)
      |> Repo.one()

    bad_version =
      if deployment_group.conditions["version"] == "" do
        false
      else
        try do
          !Version.match?(device_version, deployment_group.conditions["version"])
        rescue
          _ ->
            true
        end
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

  @spec preload_firmware_and_archive(DeploymentGroup.t()) :: DeploymentGroup.t()
  def preload_firmware_and_archive(deployment_group) do
    %DeploymentGroup{} = Repo.preload(deployment_group, [:archive, :firmware])
  end

  @spec preload_with_firmware_and_archive(Device.t()) :: Device.t()
  def preload_with_firmware_and_archive(device) do
    %Device{} = Repo.preload(device, deployment_group: [:archive, :firmware])
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
    |> where(
      [d],
      fragment(
        "?->'tags' <@ to_jsonb(?::text[]) OR (jsonb_array_length(?->'tags') = 0 and ?::text[] is null)",
        d.conditions,
        ^device.tags,
        d.conditions,
        ^device.tags
      )
    )
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

  @spec deployment_created_event(DeploymentGroup.t()) :: :ok
  defp deployment_created_event(deployment_group) do
    _ = DistributedOrchestrator.start_orchestrator(deployment_group)

    :ok
  end

  @spec deployment_activated_event(DeploymentGroup.t()) :: :ok
  defp deployment_activated_event(deployment_group) do
    _ = DistributedOrchestrator.start_orchestrator(deployment_group)

    :ok
  end

  @spec deployment_deactivated_event(DeploymentGroup.t()) :: :ok
  def deployment_deactivated_event(deployment_group) do
    _ =
      PhoenixChannelServer.broadcast(
        NervesHub.PubSub,
        "orchestrator:deployment:#{deployment_group.id}",
        "deactivated",
        %{}
      )

    :ok
  end

  @spec deployment_deleted_event(DeploymentGroup.t()) :: :ok
  defp deployment_deleted_event(deployment_group) do
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
  defp do_matched_devices(%DeploymentGroup{conditions: %{"tags" => [], "version" => version}}, query, work_type)
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
  defp do_matched_devices(%DeploymentGroup{conditions: %{"tags" => tags, "version" => ""}}, query, work_type) do
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
  defp do_matched_devices(%DeploymentGroup{conditions: %{"tags" => tags, "version" => version}}, query, work_type) do
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
