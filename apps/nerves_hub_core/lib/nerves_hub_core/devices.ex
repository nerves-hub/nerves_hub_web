defmodule NervesHubCore.Devices do
  import Ecto.Query

  alias NervesHubCore.Devices.Device
  alias NervesHubCore.Deployments.Deployment
  alias NervesHubCore.Firmwares.Firmware
  alias NervesHubCore.Accounts.Tenant
  alias NervesHubCore.Products.Product
  alias NervesHubCore.Repo
  alias Ecto.Changeset

  @uploader Application.get_env(:nerves_hub_www, :firmware_upload)

  def get_devices(%Tenant{id: tenant_id}) do
    query = from(d in Device, where: d.tenant_id == ^tenant_id)

    query
    |> Device.with_firmware()
    |> Repo.all()
  end

  def get_devices(%Product{id: product_id}) do
    query =
      from(
        d in Device,
        join: f in assoc(d, :firmware),
        where: f.product_id == ^product_id
      )

    query
    |> Device.with_firmware()
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
    |> Device.with_firmware()
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
    |> Device.with_tenant()
    |> Device.with_firmware()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_eligible_deployments(
        %Device{last_known_firmware: %Firmware{id: f_id, architecture: arch, platform: plat}} =
          device
      ) do
    from(
      d in Deployment,
      where: d.is_active,
      join: f in assoc(d, :firmware),
      where: f.architecture == ^arch,
      where: f.platform == ^plat,
      where: f.id != ^f_id
    )
    |> Repo.all()
    |> Enum.filter(fn dep -> matches_deployment?(device, dep) end)
  end

  def send_update_message(%Device{} = device, %Deployment{} = deployment) do
    with true <- matches_deployment?(device, deployment) do
      {:ok, url} = @uploader.download_file(deployment.firmware)

      NervesHubDeviceWeb.Endpoint.broadcast(
        "device:#{device.identifier}",
        "update",
        %{firmware_url: url}
      )

      {:ok, device}
    else
      _ -> {:error, :invalid_deployment_for_device}
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

  @doc """
  Returns true if Version.match? and all deployment tags are in device tags.
  """
  def matches_deployment?(
        %Device{tags: tags, last_known_firmware: %Firmware{version: version}},
        %Deployment{conditions: %{"version" => dep_version, "tags" => dep_tags}}
      ) do
    if Version.match?(version, dep_version) and tags_match?(tags, dep_tags) do
      true
    else
      false
    end
  end

  def matches_deployment?(_, _), do: false

  defp tags_match?(device_tags, deployment_tags) do
    Enum.all?(deployment_tags, fn tag -> tag in device_tags end)
  end
end
