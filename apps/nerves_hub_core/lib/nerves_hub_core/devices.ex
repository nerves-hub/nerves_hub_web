defmodule NervesHubCore.Devices do
  import Ecto.Query

  alias NervesHubCore.Devices.{Device, DeviceCertificate}
  alias NervesHubCore.Deployments.Deployment
  alias NervesHubCore.Firmwares.Firmware
  alias NervesHubCore.Accounts.Org
  alias NervesHubCore.Products.Product
  alias NervesHubCore.Repo
  alias Ecto.Changeset

  @uploader Application.get_env(:nerves_hub_core, :firmware_upload)

  def get_devices(%Org{id: org_id}) do
    query = from(d in Device, where: d.org_id == ^org_id)

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

  def get_device(%Org{id: org_id}, device_id) do
    query =
      from(
        d in Device,
        where: d.org_id == ^org_id,
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

  @spec get_device_by_identifier(Org.t(), String.t()) :: {:ok, Device.t()} | {:error, :not_found}
  def get_device_by_identifier(%Org{id: org_id}, identifier) when is_binary(identifier) do
    query =
      from(
        d in Device,
        where: d.identifier == ^identifier and d.org_id == ^org_id
      )

    query
    |> Device.with_org()
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

  def get_eligible_deployments(_), do: []

  def send_update_message(%Device{} = device, %Deployment{} = deployment) do
    with true <- matches_deployment?(device, deployment) do
      {:ok, url} = @uploader.download_file(deployment.firmware)

      Phoenix.PubSub.broadcast(
        NervesHubWeb.PubSub,
        "device_socket:#{device.id}",
        %Phoenix.Socket.Broadcast{event: "update", payload: %{firmware_url: url}}
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

  @spec create_device_certificate(Device.t(), map) ::
          {:ok, DeviceCertificate.t()}
          | {:error, Changeset.t()}
  def create_device_certificate(%Device{} = device, params) do
    device
    |> Ecto.build_assoc(:device_certificates)
    |> DeviceCertificate.changeset(params)
    |> Repo.insert()
  end

  def get_device_certificates(%Device{} = device) do
    query =
      from(
        c in DeviceCertificate,
        join: d in assoc(c, :device),
        where: d.id == ^device.id
      )

    query
    |> Repo.all()
  end

  def get_device_by_certificate(%DeviceCertificate{} = cert) do
    query =
      from(
        d in Device,
        join: c in assoc(d, :device_certificates),
        where: d.id == ^cert.device_id and c.serial == ^cert.serial
      )

    query
    |> Device.with_org()
    |> Device.with_firmware()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_device_certificate_by_serial(serial) do
    query =
      from(
        c in DeviceCertificate,
        where: c.serial == ^serial
      )

    query
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      certificate ->
        {:ok, certificate}
    end
  end

  def update_device(%Device{} = device, params) do
    device
    |> Device.changeset(params)
    |> Repo.update()
    |> case do
      {:ok, device} ->
        {:ok, Repo.preload(device, :last_known_firmware, force: true)}

      error ->
        error
    end
  end

  @doc """
  Returns true if Version.match? and all deployment tags are in device tags.
  """
  def matches_deployment?(
        %Device{tags: tags, last_known_firmware: %Firmware{version: version}},
        %Deployment{conditions: %{"version" => requirement, "tags" => dep_tags}}
      ) do
    if version_match?(version, requirement) and tags_match?(tags, dep_tags) do
      true
    else
      false
    end
  end

  def matches_deployment?(_, _), do: false

  defp version_match?(_vsn, ""), do: true

  defp version_match?(version, requirement) do
    Version.match?(version, requirement)
  end

  defp tags_match?(device_tags, deployment_tags) do
    Enum.all?(deployment_tags, fn tag -> tag in device_tags end)
  end
end
