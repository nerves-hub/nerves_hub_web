defmodule NervesHubWebCore.Devices do
  import Ecto.Query

  alias Ecto.Changeset

  alias NervesHubWebCore.{
    Deployments.Deployment,
    Firmwares,
    Firmwares.Firmware,
    Accounts.Org,
    Products.Product,
    Repo
  }

  alias NervesHubWebCore.Devices.{Device, DeviceCertificate, CACertificate}

  @uploader Application.get_env(:nerves_hub_web_core, :firmware_upload)

  def get_devices(%Org{id: org_id}) do
    query = from(d in Device, where: d.org_id == ^org_id)

    query
    |> Device.with_firmware()
    |> order_by(asc: :identifier)
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
    |> order_by(asc: :identifier)
    |> Repo.all()
  end

  defp device_by_org_query(org_id, device_id) do
    from(
      d in Device,
      where: d.org_id == ^org_id,
      where: d.id == ^device_id
    )
  end

  def get_device_by_org(%Org{id: org_id}, device_id) do
    device_by_org_query(org_id, device_id)
    |> Device.with_firmware()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_device_by_org!(%Org{id: org_id}, device_id) do
    device_by_org_query(org_id, device_id)
    |> Device.with_firmware()
    |> Repo.one!()
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
        %Device{
          last_known_firmware: %Firmware{
            id: f_id,
            architecture: arch,
            platform: plat,
            product_id: product_id
          }
        } = device
      ) do
    from(
      d in Deployment,
      where: d.is_active,
      join: f in assoc(d, :firmware),
      where: f.product_id == ^product_id,
      where: f.architecture == ^arch,
      where: f.platform == ^plat,
      where: f.id != ^f_id
    )
    |> Repo.all()
    |> Enum.filter(fn dep -> matches_deployment?(device, dep) end)
  end

  def get_eligible_deployments(_), do: []

  def send_update_message(%Device{} = device, %Deployment{} = deployment) do
    deployment = Repo.preload(deployment, :firmware, force: true)

    with true <- matches_deployment?(device, deployment) do
      {:ok, url} = @uploader.download_file(deployment.firmware)

      Phoenix.PubSub.broadcast(
        NervesHubWeb.PubSub,
        "device:#{device.id}",
        %Phoenix.Socket.Broadcast{
          event: "update",
          payload: %{device_id: device.id, firmware_url: url}
        }
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
    |> case do
      {:ok, device} ->
        Firmwares.update_firmware_ttl(device.last_known_firmware_id)
        {:ok, device}

      error ->
        error
    end
  end

  def delete_device(%Device{} = device) do
    Repo.delete(device)
    |> case do
      {:ok, device} ->
        Firmwares.update_firmware_ttl(device.last_known_firmware_id)
        {:ok, device}

      error ->
        error
    end
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

  @spec get_device_by_certificate(DeviceCertificate.t()) ::
          {:ok, Device.t()} | {:error, :not_found}
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

  def update_device_certificate(%DeviceCertificate{} = certificate, params) do
    certificate
    |> DeviceCertificate.update_changeset(params)
    |> Repo.update()
  end

  @spec create_ca_certificate(Org.t(), any()) ::
          {:ok, CACertificate.t()}
          | {:error, Changeset.t()}
  def create_ca_certificate(%Org{} = org, params) do
    org
    |> Ecto.build_assoc(:ca_certificates)
    |> CACertificate.changeset(params)
    |> Repo.insert()
  end

  def get_ca_certificates(%Org{id: org_id}) do
    from(ca in CACertificate, where: ca.org_id == ^org_id)
    |> Repo.all()
  end

  @spec get_ca_certificate_by_aki(binary) :: {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_aki(aki) do
    Repo.get_by(CACertificate, aki: aki)
    |> case do
      nil -> {:error, :not_found}
      ca_cert -> {:ok, ca_cert}
    end
  end

  @spec get_ca_certificate_by_serial(binary) :: {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_serial(serial) do
    Repo.get_by(CACertificate, serial: serial)
    |> case do
      nil -> {:error, :not_found}
      ca_cert -> {:ok, ca_cert}
    end
  end

  @spec get_ca_certificate_by_org_and_serial(Org.t(), binary) ::
          {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_org_and_serial(%Org{id: org_id}, serial) do
    query =
      from(
        ca in CACertificate,
        where: ca.serial == ^serial and ca.org_id == ^org_id
      )

    query
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      ca_certificate ->
        {:ok, ca_certificate}
    end
  end

  def update_ca_certificate(%CACertificate{} = certificate, params) do
    certificate
    |> CACertificate.update_changeset(params)
    |> Repo.update()
  end

  def delete_ca_certificate(%CACertificate{} = ca_certificate) do
    Repo.delete(ca_certificate)
  end

  def received_communication(%Device{org: _org} = device) do
    update_device(device, %{last_communication: DateTime.utc_now()})
  end

  @doc """
  Resolves the firmware identified by `fw_uuid` and sets that as `device`s last known firmware.
  """
  @spec update_last_known_firmware(Device.t(), String.t()) :: {} | {:error, :no_firmware_found}
  def update_last_known_firmware(%Device{org: org} = device, fw_uuid) do
    case Firmwares.get_firmware_by_uuid(org, fw_uuid) do
      {:ok, firmware} -> update_device(device, %{last_known_firmware_id: firmware.id})
      _ -> update_device(device, %{last_known_firmware_id: nil})
    end
  end

  def update_device(%Device{} = device, params) do
    device
    |> Device.changeset(params)
    |> Repo.update()
    |> case do
      {:ok, device} ->
        Firmwares.update_firmware_ttl(device.last_known_firmware_id)
        device = Repo.preload(device, [:last_known_firmware], force: true)

        # Get deployments with new changed device.
        # This will dispatch an update if `tags` is updated for example.
        task =
          Task.Supervisor.async(NervesHubWebCore.TaskSupervisor, fn ->
            case get_eligible_deployments(device) do
              [%Deployment{} = deployment | _] ->
                send_update_message(device, deployment)

              _ ->
                {:ok, device}
            end
          end)

        Task.await(task)
        {:ok, device}

      error ->
        error
    end
  end

  def resolve_update(_org, _deployments = []), do: %{update_available: false}

  def resolve_update(org, [%Deployment{} = deployment | _]) do
    with {:ok, firmware} <- Firmwares.get_firmware(org, deployment.firmware_id),
         {:ok, url} <- @uploader.download_file(firmware) do
      %{update_available: true, firmware_url: url}
    else
      _ -> %{update_available: false}
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
