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
  - Will force a recalculation
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
            messages = []

            deployment = Repo.preload(deployment, [:firmware], force: true)

            if Enum.any?([:conditions, :is_active], &Map.has_key?(changeset.changes, &1)) do
              create_inflight_checks(deployment)
            end

            if Map.has_key?(changeset.changes, :conditions) do
              description = "deployment #{deployment.name} conditions changed"
              AuditLogs.audit!(deployment, deployment, description)
            end

            # Trigger the new archive to get downloaded by devices
            messages =
              if Map.has_key?(changeset.changes, :archive_id) do
                description = "deployment #{deployment.name} has a new archive"
                AuditLogs.audit!(deployment, deployment, description)

                payload = %{archive_id: deployment.archive_id}
                [{"archives/updated", payload} | messages]
              else
                messages
              end

            if Map.has_key?(changeset.changes, :is_active) do
              if !deployment.is_active do
                description = "deployment #{deployment.name} is inactive"
                AuditLogs.audit!(deployment, deployment, description)
              end
            end

            messages = [{"deployments/update", %{}} | messages]

            {deployment, messages}

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, {deployment, messages}} ->
        Enum.each(messages, fn {event, payload} ->
          broadcast(deployment, event, payload)
        end)

        {:ok, deployment}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Create any matching inflight deployment checks for devices

  This includes devices that are already part of the deployment and devices
  that have no current deployment. They all will be rechecked by `NervesHub.Deployments.Calculator`

  Also clears any previous inflight checks for this deployment.
  """
  def create_inflight_checks(deployment) do
    InflightDeploymentCheck
    |> where([idc], idc.deployment_id == ^deployment.id)
    |> Repo.delete_all()

    query =
      Device
      |> select([d], %{
        deployment_id: ^deployment.id,
        device_id: d.id,
        inserted_at: ^DateTime.utc_now()
      })
      |> where([d], d.deployment_id == ^deployment.id)
      |> or_where([d], is_nil(d.deployment_id) and d.product_id == ^deployment.product_id)

    Repo.insert_all(InflightDeploymentCheck, query)
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
