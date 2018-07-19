defmodule NervesHubCore.Devices do
  import Ecto.Query

  alias NervesHubCore.Devices.Device
  alias NervesHubCore.Deployments.Deployment
  alias NervesHubCore.Accounts.Tenant
  alias NervesHubCore.Products.Product
  alias NervesHubCore.Repo
  alias Ecto.Changeset

  def get_devices(%Tenant{id: tenant_id}) do
    query = from(d in Device, where: d.tenant_id == ^tenant_id)

    query
    |> Repo.all()
  end

  def get_devices(%Product{id: product_id}) do
    query = from(d in Device, where: d.product_id == ^product_id)

    query
    |> Repo.all()
  end

  def get_device(%Tenant{id: tenant_id}, device_id) do
    query =
      from(
        d in Device,
        where: d.tenant_id == ^tenant_id,
        where: d.id == ^device_id
      )

    query
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  @spec get_device_by_identifier(String.t()) :: {:ok, Device.t()} | {:error, :not_found}
  def get_device_by_identifier(identifier) when is_binary(identifier) do
    query = from(d in Device, where: d.identifier == ^identifier)

    query
    |> Device.with_deployment()
    |> Device.with_tenant()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  @spec create_device(map) ::
          {:ok, Device.t()}
          | {:error, Changeset.t()}
  def create_device(params) do
    %Device{}
    |> Device.changeset(params)
    |> Repo.insert()
  end

  def update_device(%Device{} = device, params) do
    device
    |> Device.changeset(params)
    |> Repo.update()
  end

  def matches_deployment?(%Device{} = device, %Deployment{} = deployment) do
    with v <- deployment.conditions["version"],
         true <- v == "" or Version.match?(device.current_firmware.version, v),
         true <- Enum.all?(deployment.conditions["tags"], fn tag -> tag in device.tags end) do
      true
    else
      _ ->
        false
    end
  end

  def set_target_deployment(%Device{} = device, %Deployment{} = deployment) do
    with true <- matches_deployment?(device, deployment),
         {:ok, device} <- update_device(device, %{target_deployment_id: deployment.id}) do
      {:ok, device}
    else
      _ -> {:error, :invalid_deployment_for_device}
    end
  end
end
