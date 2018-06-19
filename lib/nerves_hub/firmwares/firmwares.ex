defmodule NervesHub.Firmwares do
  import Ecto.Query

  alias NervesHub.Accounts.{TenantKey, Tenant}
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Devices.Device
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Repo

  @spec get_firmware_by_tenant(integer()) :: [Firmware.t()]
  def get_firmware_by_tenant(tenant_id) do
    from(
      f in Firmware,
      where: f.tenant_id == ^tenant_id
    )
    |> Repo.all()
  end

  @spec get_firmware(Tenant.t(), integer()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware(%Tenant{id: tenant_id}, id) do
    Firmware
    |> Repo.get_by(id: id, tenant_id: tenant_id)
    |> case do
      nil -> {:error, :not_found}
      firmware -> {:ok, firmware}
    end
  end

  @spec get_firmware(integer()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware(id) do
    Firmware
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      firmware -> {:ok, firmware}
    end
  end

  @spec get_firmware_by_tenant_id_product_and_version(integer(), string(), string()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware_by_tenant_id_product_and_version(tenant_id, product, version) do
    Firmware
    |> Repo.get_by(tenant_id: tenant_id, product: product, version: version)
    |> case do
      nil -> {:error, :not_found}
      firmware -> {:ok, firmware}
    end
  end

  @spec create_firmware(map) ::
          {:ok, Firmware.t()}
          | {:error, Changeset.t()}
  def create_firmware(firmware) do
    %Firmware{}
    |> Firmware.changeset(firmware)
    |> Repo.insert()
  end

  @spec verify_signature(String.t(), [TenantKey.t()]) ::
          {:ok, TenantKey.t()}
          | {:error, :invalid_signature}
          | {:error, :no_public_keys}
  def verify_signature(_filepath, []), do: {:error, :no_public_keys}

  def verify_signature(filepath, keys) do
    keys
    |> Enum.find(fn key ->
      case System.cmd("fwup", ["--verify", "--public-key", key.key, "-i", filepath]) do
        {_, 0} ->
          true

        _ ->
          false
      end
    end)
    |> case do
      %TenantKey{} = key ->
        {:ok, key}

      nil ->
        {:error, :invalid_signature}
    end
  end

  @spec extract_metadata(String.t()) ::
          {:ok, String.t()}
          | {:error}
  def extract_metadata(filepath) do
    case System.cmd("fwup", ["-m", "-i", filepath]) do
      {metadata, 0} ->
        {:ok, metadata}

      _ ->
        {:error}
    end
  end

  @doc """
  Given a device, look for an active deployment where:
    - The architecture of its associated firmware and device match
    - The platform of its associated firmware and device match
    - The version of the device satisfies the version condition of the deployment (if one exists)
    - The device is assigned all tags in the deployment's "tags" condition
  """
  @spec get_eligible_firmware_update(Device.t(), Version.t()) ::
          {:ok, Firmware.t()} | {:ok, :none}
  def get_eligible_firmware_update(%Device{} = device, %Version{} = version) do
    from(
      d in Deployment,
      where: d.tenant_id == ^device.tenant_id,
      where: d.is_active == true,
      join: f in assoc(d, :firmware),
      on: f.architecture == ^device.architecture and f.platform == ^device.platform,
      preload: [firmware: f]
    )
    |> Repo.all()
    |> Enum.find(fn deployment ->
      with v <- deployment.conditions["version"],
           true <- v == "" or Version.match?(version, v),
           true <- Enum.all?(deployment.conditions["tags"], fn tag -> tag in device.tags end) do
        true
      else
        _ ->
          false
      end
    end)
    |> case do
      nil -> {:ok, :none}
      deployment -> {:ok, deployment.firmware}
    end
  end
end
