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
    |> case do
      {:ok, deployment} ->
        Firmwares.update_firmware_ttl(deployment.firmware_id)

        {:ok, deployment}
        |> Repo.reload_assoc(:firmware)
        |> update_relevant_devices()

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

  defp update_relevant_devices({:ok, %Deployment{is_active: false} = deployment}) do
    {:ok, deployment}
  end

  defp update_relevant_devices({:ok, deployment}) do
    relevant_devices =
      from(
        d in Devices.Device,
        join: f in assoc(d, :last_known_firmware),
        where: f.product_id == ^deployment.firmware.product_id,
        where: f.architecture == ^deployment.firmware.architecture,
        where: f.platform == ^deployment.firmware.platform,
        where: f.uuid != ^deployment.firmware.uuid
      )
      |> Devices.Device.with_firmware()
      |> Repo.all()

    Task.Supervisor.async_stream(NervesHubWebCore.TaskSupervisor, relevant_devices, fn device ->
      Devices.send_update_message(device, deployment)
    end)
    |> Stream.run()

    {:ok, deployment}
  end

  defp update_relevant_devices({:error, changeset}), do: {:error, changeset}
end
