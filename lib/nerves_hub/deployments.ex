defmodule NervesHub.Deployments do
  import Ecto.Query

  require Logger

  alias NervesHub.AuditLogs
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Deployments.InflightDeploymentCheck
  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias Ecto.Changeset

  def all() do
    Repo.all(Deployment)
  end

  @spec get_deployments_by_product(integer()) :: [Deployment.t()]
  def get_deployments_by_product(product_id) do
    from(
      d in Deployment,
      join: f in assoc(d, :firmware),
      where: f.product_id == ^product_id,
      preload: [{:firmware, :product}]
    )
    |> Repo.all()
  end

  @spec get_deployments_by_firmware(integer()) :: [Deployment.t()]
  def get_deployments_by_firmware(firmware_id) do
    from(d in Deployment, where: d.firmware_id == ^firmware_id)
    |> Repo.all()
  end

  def get(id) when is_integer(id) do
    case Repo.get(Deployment, id) do
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

  @spec get_by_product_and_name!(Product.t(), String.t()) :: Deployment.t()
  def get_by_product_and_name!(product, name) do
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
    |> join(:left, [d], p in assoc(d, :product))
    |> preload([d, f, p], firmware: f, product: p)
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
  - May force a recalculation if conditions or active changed
  """
  @spec update_deployment(Deployment.t(), map) :: {:ok, Deployment.t()} | {:error, Changeset.t()}
  def update_deployment(deployment, params) do
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
          recalculate_devices(deployment, changeset)

          # Inform those who care that the deployment updated
          _ = broadcast(deployment, "deployments/update")

          deployment

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp audit_changes!(deployment, changeset) do
    Enum.each(changeset.changes, fn
      {:archive_id, archive_id} ->
        # Trigger the new archive to get downloaded by devices
        payload = %{archive_id: archive_id}
        _ = broadcast(deployment, "archives/updated", payload)

        description = "deployment #{deployment.name} has a new archive"
        AuditLogs.audit!(deployment, deployment, description)

      {:conditions, _new_conditions} ->
        description = "deployment #{deployment.name} conditions changed"
        AuditLogs.audit!(deployment, deployment, description)

      {:is_active, is_active} when is_active != true ->
        description = "deployment #{deployment.name} is inactive"
        AuditLogs.audit!(deployment, deployment, description)

      _ ->
        :ignore
    end)
  end

  defp recalculate_devices(%{recalculation_type: :calculator_queue} = deployment, changeset) do
    if Enum.any?(
         [:conditions, :is_active, :recalculation_type],
         &Map.has_key?(changeset.changes, &1)
       ) do
      create_inflight_checks(deployment)
    else
      :ok
    end
  end

  # Default is to make connected devices perform the recalculation
  # within the DeviceSocket process.
  # This will eventually be deprecated
  defp recalculate_devices(deployment, changeset) do
    # Don't want the inflight calculator to continue through devices since
    # we have changed calculation types
    if changeset.changes[:recalculation_type], do: delete_inflight_checks(deployment)

    payload = %{
      id: deployment.id,
      active: deployment.is_active,
      product_id: deployment.product_id,
      platform: deployment.firmware.platform,
      architecture: deployment.firmware.architecture,
      version: deployment.firmware.version,
      conditions: deployment.conditions
    }

    conditions_changed? = Map.has_key?(changeset.changes, :conditions)
    is_active_changed? = Map.has_key?(changeset.changes, :is_active)
    activated? = is_active_changed? and deployment.is_active
    deactivated? = is_active_changed? and !deployment.is_active

    if conditions_changed? or deactivated? do
      # Wipe all devices attached to this deployment
      Device
      |> where([d], d.deployment_id == ^deployment.id)
      |> Repo.update_all(set: [deployment_id: nil])

      description = "deployment #{deployment.name} change removed all devices"
      AuditLogs.audit!(deployment, deployment, description)
    end

    if conditions_changed? and deployment.conditions["version"] in [nil, ""] and
         deployment.is_active do
      # The version condition is the only one not done with the DB.
      # This opens up a minor optimization to preemptively set matching
      # devices to the new deployment all at once since the version
      # condition can be skipped.
      #
      # This also helps with offline devices by potentially reducing the
      # need to do the expensive deployment check on next connect which
      # reduces the load when a lot of devices come online at once.
      Device
      |> where([d], d.product_id == ^deployment.product_id)
      |> where(
        [d],
        fragment("?->>'platform' = ?", d.firmware_metadata, ^deployment.firmware.platform)
      )
      |> where(
        [d],
        fragment(
          "?->>'architecture' = ?",
          d.firmware_metadata,
          ^deployment.firmware.architecture
        )
      )
      |> where([d], fragment("? <@ ?", ^deployment.conditions["tags"], d.tags))
      |> Repo.update_all(set: [deployment_id: deployment.id])
    end

    # Make sure relevant changed messages are broadcast for devices to
    # pickup and recalculate
    _ =
      cond do
        conditions_changed? ->
          # Conditions change needs attached and unattached devices to recalculate
          _ = broadcast(deployment, "deployments/changed", payload)
          broadcast(:none, "deployments/changed", payload)

        activated? ->
          # Now changed to active, so tell the none deployment devices
          broadcast(:none, "deployments/changed", payload)

        deactivated? ->
          # Tell the attached devices to recalculate
          broadcast(deployment, "deployments/changed", payload)

        true ->
          :no_broadcast
      end

    :ok
  end

  @doc """
  Create any matching inflight deployment checks for devices

  This includes devices that are already part of the deployment and devices
  that have no current deployment. They all will be rechecked by `NervesHub.Deployments.Calculator`

  Also clears any previous inflight checks for this deployment.
  """
  def create_inflight_checks(deployment) do
    delete_inflight_checks(deployment)

    query =
      Device
      |> select([d], %{
        deployment_id: ^deployment.id,
        device_id: d.id,
        inserted_at: ^DateTime.utc_now()
      })
      |> where([d], not is_nil(d.connection_last_seen_at))
      |> where(
        [d],
        d.deployment_id == ^deployment.id or
          (is_nil(d.deployment_id) and d.product_id == ^deployment.product_id)
      )
      |> where([d], d.firmware_metadata["platform"] == ^deployment.firmware.platform)
      |> where([d], d.firmware_metadata["architecture"] == ^deployment.firmware.architecture)

    Repo.insert_all(InflightDeploymentCheck, query)
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

  @spec create_deployment(map) :: {:ok, Deployment.t()} | {:error, Changeset.t()}
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
  Find all potential deployments for a device

  Based on the product, firmware platform, firmware architecture, and device tags
  """
  def alternate_deployments(device, active \\ [true, false])
  def alternate_deployments(%Device{firmware_metadata: nil}, _active), do: []

  def alternate_deployments(device, active) do
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

  @doc """
  Check that a device version matches for a deployment's conditions

  A deployment not having a version condition returns true
  """
  def version_match?(_device, %{conditions: %{"version" => ""}}), do: true

  def version_match?(device, %{conditions: %{"version" => version}}) when not is_nil(version) do
    Version.match?(device.firmware_metadata.version, version)
  end

  def version_match?(_device, _deployment), do: true

  defp ignore_same_deployment(query, %{deployment_id: nil}), do: query

  defp ignore_same_deployment(query, %{deployment_id: deployment_id}) do
    where(query, [d], d.id != ^deployment_id)
  end

  @doc """
  If the device is missing a deployment, find a matching deployment

  Do nothing if a deployment is already set
  """
  def set_deployment(%{deployment_id: nil} = device) do
    case alternate_deployments(device, [true]) do
      [] ->
        Logger.debug("No matching deployments for #{device.identifier}")

        %{device | deployment: nil}

      [deployment] ->
        device
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:deployment_id, deployment.id)
        |> Repo.update!()
        |> Repo.preload([:deployment])

      [deployment | _] ->
        Logger.debug(
          "More than one deployment matches for #{device.identifier}, setting to the first"
        )

        device
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:deployment_id, deployment.id)
        |> Repo.update!()
        |> Repo.preload([:deployment])
    end
  end

  def set_deployment(device) do
    Repo.preload(device, [:deployment])
  end
end
