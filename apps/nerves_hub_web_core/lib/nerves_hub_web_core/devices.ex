defmodule NervesHubWebCore.Devices do
  import Ecto.Query

  alias Ecto.Changeset

  alias NervesHubWebCore.{
    Deployments.Deployment,
    Firmwares,
    Firmwares.FirmwareMetadata,
    Accounts.AuditLog,
    Accounts.Org,
    Products,
    Products.Product,
    Repo
  }

  alias NervesHubWebCore.Devices.{Device, DeviceCertificate, CACertificate}

  @uploader Application.get_env(:nerves_hub_web_core, :firmware_upload)

  def audit_logs_for(%Device{id: id}) do
    device_type = to_string(Device)

    query =
      from(a in AuditLog, where: a.resource_type == ^device_type, where: a.resource_id == ^id)

    query
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def get_devices(%Org{id: org_id}) do
    query = from(d in Device, where: d.org_id == ^org_id)

    query
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
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_device_by_org!(%Org{id: org_id}, device_id) do
    device_by_org_query(org_id, device_id)
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
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_eligible_deployments(%Device{firmware_metadata: nil}), do: []

  def get_eligible_deployments(%Device{firmware_metadata: meta} = device) do
    case Products.get_product_by_org_id_and_name(device.org_id, meta.product) do
      {:ok, product} ->
        from(
          d in Deployment,
          where: d.is_active,
          join: f in assoc(d, :firmware),
          where: f.product_id == ^product.id,
          where: f.architecture == ^meta.architecture,
          where: f.platform == ^meta.platform,
          where: f.uuid != ^meta.uuid
        )
        |> Repo.all()
        |> Enum.filter(fn dep -> matches_deployment?(device, dep) end)

      _error ->
        []
    end
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
          payload: %{firmware_url: url}
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
  end

  def delete_device(%Device{} = device) do
    Repo.delete(device)
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
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_device_certificate_by_x509(cert) do
    aki = NervesHubWebCore.Certificate.get_aki(cert)
    serial = NervesHubWebCore.Certificate.get_serial_number(cert)
    {not_before, not_after} = NervesHubWebCore.Certificate.get_validity(cert)

    query =
      from(
        c in DeviceCertificate,
        where:
          c.serial == ^serial and
            c.aki == ^aki and
            c.not_before == ^not_before and
            c.not_after == ^not_after
      )

    query
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      certificate -> {:ok, certificate}
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

  def received_communication(device) do
    update_device(device, %{last_communication: DateTime.utc_now()})
  end

  def update_firmware_metadata(device, nil) do
    {:ok, device}
  end

  def update_firmware_metadata(device, metadata) do
    update_device(device, %{firmware_metadata: metadata})
  end

  def update_device(%Device{} = device, params) do
    device
    |> Device.changeset(params)
    |> Repo.update()
    |> case do
      {:ok, device} ->
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
        %Device{tags: tags, firmware_metadata: %FirmwareMetadata{version: version}},
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
