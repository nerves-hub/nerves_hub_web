defmodule NervesHubWebCore.Deployments do
  import Ecto.Query

  alias NervesHubWebCore.Deployments.Deployment
  alias NervesHubWebCore.Firmwares
  alias NervesHubWebCore.Devices
  alias NervesHubWebCore.Products.Product
  alias NervesHubWebCore.Repo
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

  @spec get_deployment_by_name(Product.t(), String.t()) ::
          {:ok, Deployment.t()} | {:error, :not_found}
  def get_deployment_by_name(%Product{id: product_id}, deployment_name) do
    from(
      d in Deployment,
      where: d.name == ^deployment_name,
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

        deployment
        |> fetch_relevant_devices()
        |> update_relevant_devices(deployment)

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
      where: d.org_id == ^org_id
    )
    |> Repo.all()
  end

  defp update_relevant_devices(devices, deployment) do
    Task.Supervisor.async_stream(NervesHubWebCore.TaskSupervisor, devices, fn device ->
      Devices.send_update_message(device, deployment)
    end)
    |> Stream.run()

    {:ok, deployment}
  end
end
