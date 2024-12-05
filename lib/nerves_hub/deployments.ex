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

  @spec get_deployment_device_counts_by_product(integer()) :: %{integer() => integer()}
  def get_deployment_device_counts_by_product(product_id) do
    Device
    |> select([d], {d.deployment_id, count(d.id)})
    |> where([d], d.product_id == ^product_id)
    |> group_by([d], d.deployment_id)
    |> Repo.all()
    |> Map.new()
  end

  @spec get_deployment_device_count(integer()) :: %{integer() => integer()}
  def get_deployment_device_count(deployment_id) do
    Device
    |> select([d], count(d.id))
    |> where([d], d.deployment_id == ^deployment_id)
    |> Repo.one()
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
      NervesHub.Workers.FirmwareDeltaBuilder.start(source_id, target_id)
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

  @spec change_deployment(Deployment.t(), map()) :: Changeset.t()
  def change_deployment(deployment, params) do
    Deployment.changeset(deployment, params)
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
  Find all potential devices for a deployment

  Based on the product, firmware platform, firmware architecture, and device tags
  """
  def estimate_devices_matched_by_conditions(product_id, platform, conditions) do
    Device
    |> where([dev], dev.product_id == ^product_id)
    |> where([dev], fragment("d0.firmware_metadata ->> 'platform'") == ^platform)
    |> where([dev], fragment("?::jsonb->'tags' <@ to_jsonb(?::text[])", ^conditions, dev.tags))
    |> Repo.all()
    |> Enum.filter(&version_match?(&1, %{conditions: conditions}))
    |> Enum.count()
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

  @spec verify_deployment_membership(Device.t()) :: Device.t()
  def verify_deployment_membership(%Device{deployment_id: deployment_id} = device)
      when not is_nil(deployment_id) do
    %{deployment: deployment} = device = Repo.preload(device, deployment: :firmware)
    bad_architecture = device.firmware_metadata.architecture != deployment.firmware.architecture
    bad_platform = device.firmware_metadata.platform != deployment.firmware.platform

    reason =
      cond do
        bad_architecture and bad_platform ->
          :bad_architecture_and_platform

        bad_architecture ->
          :bad_architecture

        bad_platform ->
          :bad_platform

        true ->
          nil
      end

    if reason do
      device =
        device
        |> Ecto.Changeset.change(%{deployment_id: nil, deployment_conflict: reason})
        |> Repo.update!()

      AuditLogs.audit!(
        device,
        device,
        "device no longer matches deployment's #{deployment.name} requirements because of #{reason}"
      )
    else
      device
    end
  end

  def verify_deployment_membership(device), do: device
end
