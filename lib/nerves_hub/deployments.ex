defmodule NervesHub.Deployments do
  import Ecto.Query

  require Logger

  alias NervesHub.AuditLogs
  alias NervesHub.Deployments.Deployment
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

  Updating a deployment is a big task. Devices will be notified of the change when:
  - Firmware changes, all devices will be told of the new firmware to update
  - Conditions change, all devices will have the deployment removed and told about the
    change, any devices that don't have a deployment and are online will be told about
    the conditions changing to check for a deployment again
  - If now active, any devices without a deployment will be told to reevaluate
  - If now inactive, devices will have the deployment removed and told about the change
  """
  @spec update_deployment(Deployment.t(), map) :: {:ok, Deployment.t()} | {:error, Changeset.t()}
  def update_deployment(deployment, params) do
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

        payload = %{
          id: deployment.id,
          active: deployment.is_active,
          product_id: deployment.product_id,
          platform: deployment.firmware.platform,
          architecture: deployment.firmware.architecture,
          version: deployment.firmware.version,
          conditions: deployment.conditions
        }

        # if the conditions changed, we should reset all devices and tell any connected
        if Map.has_key?(changeset.changes, :conditions) do
          Device
          |> where([d], d.deployment_id == ^deployment.id)
          |> Repo.update_all(set: [deployment_id: nil])

          if deployment.conditions["version"] in [nil, ""] and deployment.is_active do
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

          _ = broadcast(deployment, "deployments/changed", payload)
          _ = broadcast(:none, "deployments/changed", payload)

          description = "deployment #{deployment.name} conditions changed and removed all devices"
          AuditLogs.audit!(deployment, deployment, description)
        end

        # Trigger the new archive to get downloaded by devices
        if Map.has_key?(changeset.changes, :archive_id) do
          payload = %{
            archive_id: deployment.archive_id
          }

          _ = broadcast(deployment, "archives/updated", payload)

          description = "deployment #{deployment.name} has a new archive"
          AuditLogs.audit!(deployment, deployment, description)
        end

        # if is_active is false, wipe it out like above
        # if its now true, tell the none deployment devices
        if Map.has_key?(changeset.changes, :is_active) do
          if deployment.is_active do
            broadcast(:none, "deployments/changed", payload)
          else
            Device
            |> where([d], d.deployment_id == ^deployment.id)
            |> Repo.update_all(set: [deployment_id: nil])

            _ = broadcast(deployment, "deployments/changed", payload)

            description = "deployment #{deployment.name} is inactive and removed all devices"
            AuditLogs.audit!(deployment, deployment, description)
          end
        end

        # Firmware changed on active deployment
        if deployment.is_active and Map.has_key?(changeset.changes, :firmware_id) do
          deployment = Repo.preload(deployment, :product, force: true)

          if deployment.product.delta_updatable do
            trigger_delta_generation_for_deployment(deployment)
          end
        end

        _ = broadcast(deployment, "deployments/update")

        {:ok, deployment}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp trigger_delta_generation_for_deployment(deployment) do
    case NervesHub.Devices.get_device_firmware_for_delta_generation_by_deployment(deployment.id) do
      {:ok, %{rows: rows}} ->
        rows
        |> Enum.map(fn [source_id, target_id] ->
          {source_id, target_id}
        end)
        |> Enum.uniq()
        |> Enum.each(fn {source_id, target_id} ->
          NervesHub.Workers.FirmwareDeltaBuilder.start(source_id, target_id)
        end)

        :ok

      error ->
        error
    end
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
