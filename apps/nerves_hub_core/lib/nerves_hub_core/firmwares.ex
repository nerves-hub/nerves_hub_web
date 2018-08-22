defmodule NervesHubCore.Firmwares do
  import Ecto.Query

  alias NervesHubCore.Accounts.{OrgKey, Org}
  alias NervesHubCore.Firmwares.Firmware
  alias NervesHubCore.Products
  alias NervesHubCore.Repo

  @spec get_firmwares_by_product(integer()) :: [Firmware.t()]
  def get_firmwares_by_product(product_id) do
    from(
      f in Firmware,
      where: f.product_id == ^product_id
    )
    |> Firmware.with_product()
    |> Repo.all()
  end

  @spec get_firmware(Org.t(), integer()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware(%Org{id: org_id}, id) do
    from(
      f in Firmware,
      where: f.id == ^id,
      join: p in assoc(f, :product),
      where: p.org_id == ^org_id
    )
    |> Firmware.with_product()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      firmware -> {:ok, firmware}
    end
  end

  @spec get_firmware_by_product_and_version(Org.t(), String.t(), String.t()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware_by_product_and_version(%Org{} = org, product, version) do
    Firmware
    |> Repo.get_by(org_id: org.id, product: product, version: version)
    |> case do
      nil -> {:error, :not_found}
      firmware -> {:ok, firmware}
    end
  end

  @spec get_firmware_by_uuid(Org.t(), String.t()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware_by_uuid(%Org{id: t_id}, uuid) do
    from(
      f in Firmware,
      where: f.uuid == ^uuid,
      join: p in assoc(f, :product),
      preload: [product: p],
      where: p.org_id == ^t_id
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      firmware -> {:ok, firmware}
    end
  end

  @spec prepare_firmware_params(Org.t(), binary) ::
          {:ok, map}
          | {:error, :no_public_keys}
          | {:error, :invalid_signature}
          | {:error, any}
  def prepare_firmware_params(%Org{} = org, filepath) do
    org = NervesHubCore.Repo.preload(org, :org_keys)

    with {:ok, %{id: org_key_id}} <- verify_signature(filepath, org.org_keys),
         {:ok, metadata} <- extract_metadata(filepath),
         {:ok, architecture} <- Firmware.fetch_metadata_item(metadata, "meta-architecture"),
         {:ok, platform} <- Firmware.fetch_metadata_item(metadata, "meta-platform"),
         {:ok, product_name} <- Firmware.fetch_metadata_item(metadata, "meta-product"),
         {:ok, version} <- Firmware.fetch_metadata_item(metadata, "meta-version"),
         author <- Firmware.get_metadata_item(metadata, "meta-author"),
         description <- Firmware.get_metadata_item(metadata, "meta-description"),
         misc <- Firmware.get_metadata_item(metadata, "meta-misc"),
         uuid <- Firmware.get_metadata_item(metadata, "meta-uuid"),
         vcs_identifier <- Firmware.get_metadata_item(metadata, "meta-vcs-identifier"),
         {:ok, upload_metadata} <- upload_firmware(filepath, uuid <> ".fw", org.id) do
      {:ok,
       %{
         architecture: architecture,
         author: author,
         description: description,
         misc: misc,
         platform: platform,
         product_name: product_name,
         org_id: org.id,
         org_key_id: org_key_id,
         upload_metadata: upload_metadata,
         uuid: uuid,
         vcs_identifier: vcs_identifier,
         version: version
       }}
    end
  end

  @spec create_firmware(map) ::
          {:ok, Firmware.t()}
          | {:error, Changeset.t()}
  def create_firmware(%{product_name: product_name} = params) when is_binary(product_name) do
    with {:ok, product} <- Products.get_product_by_org_id_and_name(params.org_id, product_name) do
      params
      |> Map.put(:product_id, product.id)
      |> do_create_firmware()
    else
      _ -> do_create_firmware(params)
    end
  end

  def create_firmware(params) do
    do_create_firmware(params)
  end

  defp do_create_firmware(params) do
    %Firmware{}
    |> Firmware.changeset(params)
    |> Repo.insert()
  end

  def delete_firmware(%Firmware{} = firmware) do
    if uploader = Application.get_env(:nerves_hub_core, :firmware_upload) do
      uploader.delete_file(firmware)
    end

    Repo.delete(firmware)
  end

  @spec verify_signature(String.t(), [OrgKey.t()]) ::
          {:ok, OrgKey.t()}
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
      %OrgKey{} = key ->
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

      _error ->
        {:error}
    end
  end

  def upload_firmware(filepath, filename, org_id) do
    if uploader = Application.get_env(:nerves_hub_core, :firmware_upload) do
      uploader.upload_file(filepath, filename, org_id)
    else
      {:error}
    end
  end
end
