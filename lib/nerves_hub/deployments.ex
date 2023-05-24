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

  @spec get_deployment_by_name(Product.t(), String.t()) ::
          {:ok, Deployment.t()} | {:error, :not_found}
  def get_deployment_by_name(%Product{id: product_id}, deployment_name) do
    from(
      d in Deployment,
      where: d.name == ^deployment_name,
      join: f in assoc(d, :firmware),
      where: f.product_id == ^product_id
    )
    |> Deployment.with_firmware()
    |> Deployment.with_product()
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      deployment ->
        {:ok, deployment}
    end
  end

  @spec delete_deployment(Deployment.t()) :: {:ok, Deployment.t()} | {:error, :not_found}
  def delete_deployment(%Deployment{id: deployment_id}) do
    case Repo.delete(Repo.get!(Deployment, deployment_id)) do
      {:error, _changeset} ->
        {:error, :not_found}

      {:ok, deployment} ->
        broadcast(:monitor, "deployments/delete", %{deployment_id: deployment.id})

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

          broadcast(deployment, "deployments/changed", payload)
          broadcast(:none, "deployments/changed", payload)

          description = "deployment #{deployment.name} conditions changed and removed all devices"
          AuditLogs.audit!(deployment, deployment, :update, description)
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

            broadcast(deployment, "deployments/changed", payload)

            description = "deployment #{deployment.name} is inactive and removed all devices"
            AuditLogs.audit!(deployment, deployment, :update, description)
          end
        end

        broadcast(deployment, "deployments/update")

        {:ok, deployment}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec create_deployment(map) :: {:ok, Deployment.t()} | {:error, Changeset.t()}
  def create_deployment(params) do
    changeset = Deployment.creation_changeset(%Deployment{}, params)

    case Repo.insert(changeset) do
      {:ok, deployment} ->
        broadcast(:monitor, "deployments/new", %{deployment_id: deployment.id})

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
  def alternate_deployments(%Device{firmware_metadata: nil}), do: []

  def alternate_deployments(device, active \\ [true, false]) do
    Deployment
    |> join(:inner, [d], assoc(d, :firmware), as: :firmware)
    |> where([d], d.product_id == ^device.product_id)
    |> where([d], d.is_active in ^active)
    |> ignore_same_deployment(device)
    |> where([d, firmware: f], f.platform == ^device.firmware_metadata.platform)
    |> where([d, firmware: f], f.architecture == ^device.firmware_metadata.architecture)
    |> where([d], fragment("?->'tags' <@ to_jsonb(?::text[])", d.conditions, ^device.tags))
    |> Repo.all()
    |> Enum.filter(fn deployment ->
      version_match?(device, deployment)
    end)
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

  def set_deployment(device), do: Repo.preload(device, [:deployment])
end
