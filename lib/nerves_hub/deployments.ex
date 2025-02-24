defmodule NervesHub.Deployments do
  import Ecto.Query

  require Logger

  alias NervesHub.AuditLogs.DeploymentTemplates
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Deployments.InflightDeploymentCheck
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product
  alias NervesHub.Workers.FirmwareDeltaBuilder

  alias NervesHub.Repo

  alias Ecto.Changeset

  @spec all() :: [Deployment.t()]
  def all() do
    Repo.all(Deployment)
  end

  @spec filter(Product.t(), map()) :: {[Product.t()], Flop.Meta.t()}
  def filter(product, opts \\ %{}) do
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) end)

    sort = Map.get(opts, :sort, "name")
    sort_direction = Map.get(opts, :sort_direction, "desc")

    sort_opts = {String.to_existing_atom(sort_direction), String.to_atom(sort)}

    flop = %Flop{
      page: String.to_integer(Map.get(opts, :page, "1")),
      page_size: String.to_integer(Map.get(opts, :page_size, "25"))
    }

    subquery =
      Device
      |> select([d], %{
        deployment_id: d.deployment_id,
        device_count: count()
      })
      |> Repo.exclude_deleted()
      |> group_by([d], d.deployment_id)

    Deployment
    |> join(:left, [d], dev in subquery(subquery), on: dev.deployment_id == d.id)
    |> join(:left, [d], f in assoc(d, :firmware))
    |> where([d], d.product_id == ^product.id)
    |> sort_deployments(sort_opts)
    |> preload([_d, _dev, f], firmware: f)
    |> select_merge([_f, dev], %{device_count: dev.device_count})
    |> Flop.run(flop)
  end

  defp sort_deployments(query, {direction, :platform}) do
    order_by(query, [_d, _dev, f], {^direction, f.platform})
  end

  defp sort_deployments(query, {direction, :architecture}) do
    order_by(query, [_d, _dev, f], {^direction, f.architecture})
  end

  defp sort_deployments(query, {direction, :device_count}) do
    order_by(query, [_d, dev], {^direction, dev.device_count})
  end

  defp sort_deployments(query, {direction, :firmware_version}) do
    order_by(query, [_d, _dev, f], {^direction, f.version})
  end

  defp sort_deployments(query, sort), do: order_by(query, ^sort)

  @spec get_deployments_by_product(Product.t()) :: [Deployment.t()]
  def get_deployments_by_product(%Product{id: product_id}) do
    from(
      d in Deployment,
      join: f in assoc(d, :firmware),
      where: f.product_id == ^product_id,
      preload: [{:firmware, :product}]
    )
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

  @spec get_device_count(Deployment.t()) :: term() | nil
  def get_device_count(%Deployment{id: id}) do
    Device
    |> where([d], d.deployment_id == ^id)
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  @spec get_deployments_by_firmware(integer()) :: [Deployment.t()]
  def get_deployments_by_firmware(firmware_id) do
    Deployment
    |> where([d], d.firmware_id == ^firmware_id)
    |> Repo.all()
  end

  @spec get(integer()) :: {:ok, Deployment.t()} | {:error, :not_found}
  def get(id) when is_integer(id) do
    case Repo.get(Deployment, id) do
      nil ->
        {:error, :not_found}

      deployment ->
        {:ok, deployment}
    end
  end

  @spec get_deployment_for_device(Device.t()) :: {:ok, Deployment.t()} | {:error, :not_found}
  def get_deployment_for_device(%Device{deployment_id: deployment_id}) do
    Deployment
    |> where([d], d.id == ^deployment_id)
    |> join(:left, [d], f in assoc(d, :firmware))
    |> preload([d, f], firmware: f)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      deployment ->
        {:ok, deployment}
    end
  end

  @spec get_deployment(Product.t(), String.t()) :: {:ok, Deployment.t()} | {:error, :not_found}
  def get_deployment(%Product{id: product_id}, deployment_id) do
    from(
      d in Deployment,
      where: d.id == ^deployment_id,
      join: f in assoc(d, :firmware),
      where: f.product_id == ^product_id,
      preload: [{:firmware, :product}]
    )
    |> Deployment.with_firmware()
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      deployment ->
        {:ok, deployment}
    end
  end

  def get_deployment!(deployment_id), do: Repo.get!(Deployment, deployment_id)

  @spec get_by_product_and_name!(Product.t(), String.t(), boolean()) :: Deployment.t()
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

  @spec get_deployment_by_name(Product.t(), String.t()) ::
          {:ok, Deployment.t()} | {:error, :not_found}
  def get_deployment_by_name(product, name) do
    get_by_product_and_name_query(product, name)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      deployment ->
        {:ok, deployment}
    end
  end

  defp get_by_product_and_name_query(%Product{id: product_id}, name) do
    Deployment
    |> where(name: ^name)
    |> where(product_id: ^product_id)
    |> join(:left, [d], f in assoc(d, :firmware))
    |> join(:left, [d], a in assoc(d, :archive))
    |> join(:left, [d], p in assoc(d, :product))
    |> preload([d, f, a, p], firmware: f, archive: a, product: p)
  end

  @spec delete_deployment(Deployment.t()) :: {:ok, Deployment.t()} | {:error, :not_found}
  def delete_deployment(%Deployment{id: deployment_id}) do
    case Repo.delete(Repo.get!(Deployment, deployment_id)) do
      {:error, _changeset} ->
        {:error, :not_found}

      {:ok, deployment} ->
        _ = broadcast(:monitor, "deployments/delete", %{deployment_id: deployment.id})

        {:ok, deployment}
    end
  end

  @doc """
  Update a deployment

  - Records audit logs depending on changes
  """
  @spec update_deployment(Deployment.t(), map) :: {:ok, Deployment.t()} | {:error, Changeset.t()}
  def update_deployment(deployment, params) do
    result =
      Repo.transaction(fn ->
        device_count =
          Device
          |> select([d], count(d))
          |> where([d], d.deployment_id == ^deployment.id)
          |> Repo.one()

        changeset =
          deployment
          |> Deployment.with_firmware()
          |> Deployment.changeset(params)
          |> Ecto.Changeset.put_change(:total_updating_devices, device_count)

        case Repo.update(changeset) do
          {:ok, deployment} ->
            deployment = Repo.preload(deployment, [:firmware], force: true)

            audit_changes!(deployment, changeset)

            {deployment, changeset}

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, {deployment, changeset}} ->
        _ = maybe_trigger_delta_generation(deployment, changeset)
        :ok = broadcast(deployment, "deployments/update")

        {:ok, deployment}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp audit_changes!(deployment, changeset) do
    Enum.each(changeset.changes, fn
      {:archive_id, archive_id} ->
        # Trigger the new archive to get downloaded by devices
        payload = %{archive_id: archive_id}
        _ = broadcast(deployment, "archives/updated", payload)

        DeploymentTemplates.audit_deployment_change(deployment, "has a new archive")

      {:conditions, _new_conditions} ->
        DeploymentTemplates.audit_deployment_change(deployment, "conditions changed")

      {:is_active, is_active} when is_active != true ->
        DeploymentTemplates.audit_deployment_change(deployment, "is inactive")

      _ ->
        :ignore
    end)
  end

  defp maybe_trigger_delta_generation(deployment, changeset) do
    # Firmware changed on active deployment
    if deployment.is_active and Map.has_key?(changeset.changes, :firmware_id) do
      deployment = Repo.preload(deployment, :product, force: true)

      if deployment.product.delta_updatable do
        trigger_delta_generation_for_deployment(deployment)
      end
    end
  end

  defp trigger_delta_generation_for_deployment(deployment) do
    NervesHub.Devices.get_device_firmware_for_delta_generation_by_deployment(deployment.id)
    |> Enum.uniq()
    |> Enum.each(fn {source_id, target_id} ->
      FirmwareDeltaBuilder.start(source_id, target_id)
    end)
  end

  @doc """
  Delete any matching inflight deployment checks for devices
  """
  @spec delete_inflight_checks(Deployment.t()) :: :ok
  def delete_inflight_checks(deployment) do
    _ =
      InflightDeploymentCheck
      |> where([idc], idc.deployment_id == ^deployment.id)
      |> Repo.delete_all()

    :ok
  end

  @spec new_deployment() :: Changeset.t()
  def new_deployment() do
    Ecto.Changeset.change(%Deployment{})
  end

  @spec change_deployment(Deployment.t(), map()) :: Changeset.t()
  def change_deployment(deployment, params) do
    Deployment.changeset(deployment, params)
  end

  @spec create_deployment(map()) :: {:ok, Deployment.t()} | {:error, Changeset.t()}
  def create_deployment(params) do
    changeset = Deployment.creation_changeset(%Deployment{}, params)

    case Repo.insert(changeset) do
      {:ok, deployment} ->
        _ = broadcast(:monitor, "deployments/new", %{deployment_id: deployment.id})

        {:ok, deployment}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec broadcast(Deployment.t() | atom(), String.t(), map()) :: :ok | {:error, term()}
  def broadcast(deployment, event, payload \\ %{})

  def broadcast(:none, event, payload) do
    message = %Phoenix.Socket.Broadcast{
      topic: "deployment:none",
      event: event,
      payload: payload
    }

    Phoenix.PubSub.broadcast(NervesHub.PubSub, "deployment:none", message)
  end

  def broadcast(:monitor, event, payload) do
    Phoenix.PubSub.broadcast(
      NervesHub.PubSub,
      "deployment:monitor",
      %Phoenix.Socket.Broadcast{event: event, payload: payload}
    )
  end

  def broadcast(%Deployment{id: id}, event, payload) do
    message = %Phoenix.Socket.Broadcast{
      topic: "deployment:#{id}",
      event: event,
      payload: payload
    }

    Phoenix.PubSub.broadcast(NervesHub.PubSub, "deployment:#{id}", message)
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

  defp version_match?(_device, _deployment), do: true

  @spec verify_deployment_membership(Device.t()) :: Device.t()
  def verify_deployment_membership(
        %Device{deployment_id: deployment_id, firmware_metadata: %{version: device_version}} =
          device
      )
      when not is_nil(deployment_id) do
    {:ok, deployment} = get_deployment_for_device(device)

    bad_version = !Version.match?(device_version, deployment.conditions["version"])
    bad_platform = device.firmware_metadata.platform != deployment.firmware.platform
    bad_architecture = device.firmware_metadata.architecture != deployment.firmware.architecture

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

      DeploymentTemplates.audit_deployment_mismatch(device, deployment, reason)

      device
    else
      device
    end
  end

  def verify_deployment_membership(device), do: device

  @doc """
  If the device is missing a deployment, find a matching deployment

  Do nothing if a deployment is already set
  """
  @spec set_deployment(Device.t()) :: Device.t()
  def set_deployment(%{deployment_id: nil} = device) do
    case matching_deployments(device, [true]) do
      [] ->
        set_deployment_telemetry(:none_found, device)

        %{device | deployment: nil}

      [deployment] ->
        set_deployment_telemetry(:one_found, device, deployment)

        DeviceTemplates.audit_set_deployment(device, deployment, :one_found)

        Devices.update_deployment(device, deployment)

      [deployment | _] ->
        set_deployment_telemetry(:multiple_found, device, deployment)

        DeviceTemplates.audit_set_deployment(device, deployment, :multiple_found)

        Devices.update_deployment(device, deployment)
    end
  end

  def set_deployment(device) do
    preload_with_firmware_and_archive(device)
  end

  defp set_deployment_telemetry(result, device, deployment \\ nil) do
    metadata = %{device: device}

    metadata =
      if deployment do
        Map.put(metadata, :deployment, deployment)
      else
        metadata
      end

    :telemetry.execute(
      [:nerves_hub, :deployments, :set_deployment, result],
      %{count: 1},
      metadata
    )
  end

  @spec preload_firmware_and_archive(Deployment.t()) :: Deployment.t()
  def preload_firmware_and_archive(deployment) do
    %Deployment{} = Repo.preload(deployment, [:archive, :firmware])
  end

  @spec preload_with_firmware_and_archive(Device.t(), boolean()) :: Device.t()
  def preload_with_firmware_and_archive(device, force \\ false) do
    %Device{} = Repo.preload(device, [deployment: [:archive, :firmware]], force: force)
  end

  @doc """
  Find all potential deployments for a device

  Based on the product, firmware platform, firmware architecture, and device tags
  """
  @spec matching_deployments(Device.t(), [boolean()]) :: [Deployment.t()]
  def matching_deployments(device, active \\ [true, false])
  def matching_deployments(%Device{firmware_metadata: nil}, _active), do: []

  def matching_deployments(device, active) do
    Deployment
    |> join(:inner, [d], assoc(d, :firmware), as: :firmware)
    |> preload([_, firmware: f], firmware: f)
    |> where([d], d.product_id == ^device.product_id)
    |> where([d], d.is_active in ^active)
    |> ignore_same_deployment(device)
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

  defp ignore_same_deployment(query, %{deployment_id: nil}), do: query

  defp ignore_same_deployment(query, %{deployment_id: deployment_id}) do
    where(query, [d], d.id != ^deployment_id)
  end

  @doc """
  Find all eligible deployments for a device, based on the firmware platform,
  firmware architecture, and product.

  This is purposefully less-strict then Deployments.matching_deployments/2
  and should only be used when a human is choosing the deployment for a device.
  """
  @spec eligible_deployments(Device.t()) :: [Deployment.t()]
  def eligible_deployments(%Device{firmware_metadata: nil}), do: []

  def eligible_deployments(device) do
    Deployment
    |> join(:inner, [d], assoc(d, :firmware), as: :firmware)
    |> preload([_, firmware: f], firmware: f)
    |> where([d, _], d.product_id == ^device.product_id)
    |> where([d, firmware: f], f.platform == ^device.firmware_metadata.platform)
    |> where([d, firmware: f], f.architecture == ^device.firmware_metadata.architecture)
    |> Repo.all()
  end
end
