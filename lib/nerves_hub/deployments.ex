defmodule NervesHub.Deployments do
  import Ecto.Query

  alias NervesHub.AuditLogs
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Firmwares
  alias NervesHub.Devices
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias Ecto.Changeset

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
    Repo.get!(Deployment, deployment_id)
    |> Repo.delete()
    |> case do
      {:error, _changeset} ->
        {:error, :not_found}

      {:ok, deployment} ->
        Firmwares.update_firmware_ttl(deployment.firmware_id)
        {:ok, deployment}
    end
  end

  @spec update_deployment(Deployment.t(), map) :: {:ok, Deployment.t()} | {:error, Changeset.t()}
  def update_deployment(deployment, params) do
    deployment
    |> Deployment.with_firmware()
    |> Deployment.changeset(params)
    |> Repo.update()
    |> Repo.reload_assoc(:firmware)
    |> case do
      {:ok, deployment} ->
        Firmwares.update_firmware_ttl(deployment.firmware_id)
        fetch_and_update_relevant_devices(deployment)

      error ->
        error
    end
  end

  @spec create_deployment(map) :: {:ok, Deployment.t()} | {:error, Changeset.t()}
  def create_deployment(params) do
    %Deployment{}
    |> Deployment.creation_changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, deployment} ->
        Firmwares.update_firmware_ttl(deployment.firmware_id)
        {:ok, deployment}

      error ->
        error
    end
  end

  @spec failure_rate_met?(Deployment.t()) :: boolean()
  def failure_rate_met?(%Deployment{} = deployment) do
    deployment = Repo.preload(deployment, :firmware)
    rate_seconds_ago = Timex.shift(DateTime.utc_now(), seconds: -deployment.failure_rate_seconds)

    from(
      al in NervesHub.AuditLogs.AuditLog,
      where: [actor_type: ^to_string(Deployment), resource_type: ^to_string(Devices.Device)],
      where: al.actor_id == ^deployment.id,
      where:
        fragment(
          """
          (params->>'firmware_uuid' = ?) AND
          (params->>'send_update_message' = 'true')
          """,
          ^deployment.firmware.uuid
        ),
      where: al.inserted_at >= ^rate_seconds_ago,
      group_by: :resource_id,
      having: count(al.resource_id) > 2,
      select: al.resource_id
    )
    |> Repo.all()
    |> length()
    |> Kernel.>=(deployment.failure_rate_amount)
  end

  @spec failure_threshold_met?(Deployment.t()) :: boolean()
  def failure_threshold_met?(%Deployment{} = deployment) do
    deployment = Repo.preload(deployment, [:product, :firmware])

    from(
      d in Devices.Device,
      where:
        fragment(
          """
          (firmware_metadata->>'product' = ?) AND
          (firmware_metadata->>'architecture' = ?) AND
          (firmware_metadata->>'platform' = ?) AND
          (firmware_metadata->>'uuid' != ?)
          """,
          ^deployment.product.name,
          ^deployment.firmware.architecture,
          ^deployment.firmware.platform,
          ^deployment.firmware.uuid
        ),
      where: d.org_id == ^deployment.product.org_id,
      where: d.healthy == false,
      select: count(d.id)
    )
    |> Repo.exclude_deleted()
    |> Repo.one()
    |> Kernel.>=(deployment.failure_threshold)
  end

  @spec verify_eligibility(Deployment.t()) :: {:error, Ecto.Changeset.t()} | {:ok, Deployment.t()}
  def verify_eligibility(%Deployment{healthy: false} = deployment) do
    {:ok, deployment}
  end

  def verify_eligibility(%Deployment{} = deployment) do
    cond do
      failure_rate_met?(deployment) ->
        description =
          "deployment #{deployment.name} marked unhealthy. Device failure rate met for firmware #{deployment.firmware.uuid} in deployment #{deployment.name}"

        AuditLogs.audit!(deployment, deployment, :update, description, %{
          healthy: false,
          reason: "failure rate met"
        })

        update_deployment(deployment, %{healthy: false})

      failure_threshold_met?(deployment) ->
        description =
          "deployment #{deployment.name} marked unhealthy. Device failure thredhold met for firmware #{deployment.firmware.uuid} in deployment #{deployment.name}"

        AuditLogs.audit!(deployment, deployment, :update, description, %{
          healthy: false,
          reason: "failure threshold met"
        })

        update_deployment(deployment, %{healthy: false})

      true ->
        {:ok, deployment}
    end
  end

  def fetch_and_update_relevant_devices(deployment) do
    deployment
    |> fetch_relevant_devices()
    |> update_relevant_devices(deployment)
  end

  def fetch_relevant_devices(%Deployment{is_active: false}) do
    []
  end

  def fetch_relevant_devices(deployment) do
    deployment = Repo.preload(deployment, [:product, :firmware])
    org_id = deployment.product.org_id

    from(
      d in Devices.Device,
      where:
        fragment(
          """
          (firmware_metadata->>'product' = ?) AND
          (firmware_metadata->>'architecture' = ?) AND
          (firmware_metadata->>'platform' = ?) AND
          (firmware_metadata->>'uuid' != ?)
          """,
          ^deployment.product.name,
          ^deployment.firmware.architecture,
          ^deployment.firmware.platform,
          ^deployment.firmware.uuid
        ),
      where: d.org_id == ^org_id,
      where: d.healthy
    )
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  defp update_relevant_devices(devices, deployment) do
    Task.Supervisor.async_stream(
      NervesHub.TaskSupervisor,
      devices,
      fn device ->
        Devices.send_update_message(device, deployment)
      end,
      timeout: 15000
    )
    |> Stream.run()

    {:ok, deployment}
  end
end
