defmodule NervesHub.Firmwares do
  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Accounts.Org
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.FirmwareTransfer
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  require Logger

  @type upload_file_2 :: (filepath :: String.t(), filename :: String.t() -> :ok | {:error, any()})

  defp firmware_upload_config(), do: Application.fetch_env!(:nerves_hub, :firmware_upload)

  @spec get_firmwares_by_product(integer()) :: [Firmware.t()]
  def get_firmwares_by_product(product_id) do
    Firmware
    |> where([f], f.product_id == ^product_id)
    |> order_by([f], [fragment("? collate numeric desc", f.version), desc: :inserted_at])
    |> with_product()
    |> Repo.all()
  end

  def get_firmwares_for_deployment(deployment) do
    deployment = Repo.preload(deployment, [:firmware])

    Firmware
    |> where([f], f.product_id == ^deployment.product_id)
    |> where([f], f.platform == ^deployment.firmware.platform)
    |> where([f], f.architecture == ^deployment.firmware.architecture)
    |> order_by([f], [fragment("? collate numeric desc", f.version), desc: :inserted_at])
    |> with_product()
    |> Repo.all()
  end

  @doc """
  Get only version numbers for a product, sorted highest first
  """
  def get_firmware_versions_by_product(product_id) do
    Firmware
    |> select([f], f.version)
    |> distinct(true)
    |> where([f], f.product_id == ^product_id)
    |> Repo.all()
    |> Enum.sort(Version)
    |> Enum.reverse()
  end

  @spec get_firmware(Org.t(), integer()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware(%Org{id: org_id}, id) do
    Firmware
    |> with_product()
    |> where([f], f.id == ^id)
    |> where([f, p], p.org_id == ^org_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      firmware -> {:ok, firmware}
    end
  end

  def get_firmware!(firmware_id), do: Repo.get!(Firmware, firmware_id)

  def get_firmware_for_device(%Device{firmware_metadata: nil}), do: []

  def get_firmware_for_device(device) do
    Firmware
    |> where([f], f.platform == ^device.firmware_metadata.platform)
    |> where([f], f.architecture == ^device.firmware_metadata.architecture)
    |> where([f], f.org_id == ^device.org_id)
    |> where([f], f.product_id == ^device.product_id)
    |> order_by([f], fragment("? collate numeric desc", f.version))
    |> Repo.all()
  end

  @spec get_firmware_by_org_id(non_neg_integer()) :: [Firmware.t()]
  def get_firmware_by_org_id(org_id) do
    Firmware
    |> with_product()
    |> where([f, p], p.org_id == ^org_id)
    |> Repo.all()
  end

  @spec get_firmware_by_uuid(String.t()) :: Firmware.t() | nil
  def get_firmware_by_uuid(uuid) do
    Repo.get_by(Firmware, uuid: uuid)
  end

  @spec get_firmware_by_product_and_uuid!(Product.t(), String.t()) :: Firmware.t()
  def get_firmware_by_product_and_uuid!(product, uuid) do
    get_firmware_by_product_and_uuid_query(product, uuid)
    |> Repo.one!()
  end

  @spec get_firmware_by_product_and_uuid(Product.t(), String.t()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware_by_product_and_uuid(product, uuid) do
    get_firmware_by_product_and_uuid_query(product, uuid)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      firmware -> {:ok, firmware}
    end
  end

  defp get_firmware_by_product_and_uuid_query(%Product{id: product_id}, uuid) do
    Firmware
    |> with_product()
    |> where([f], f.uuid == ^uuid)
    |> where([f, p], p.id == ^product_id)
  end

  @spec create_firmware(
          org :: Org.t(),
          filepath :: Path.t(),
          opts :: [{:upload_file_2, upload_file_2()}]
        ) ::
          {:ok, Firmware.t()}
          | {:error, Changeset.t() | :no_public_keys | :invalid_signature | any}
  def create_firmware(org, filepath, opts \\ []) do
    upload_file_2 = opts[:upload_file_2] || (&firmware_upload_config().upload_file/2)

    Repo.transaction(
      fn ->
        with {:ok, params} <- build_firmware_params(org, filepath),
             {:ok, firmware} <- insert_firmware(params),
             :ok <- upload_file_2.(filepath, firmware.upload_metadata) do
          _ = NervesHubWeb.Endpoint.broadcast("firmware", "created", %{firmware: firmware})
          firmware
        else
          {:error, error} ->
            Logger.error(fn -> "Error while publishing firmware: #{inspect(error)}" end)
            Repo.rollback(error)
        end
      end,
      timeout: 30_000
    )
  end

  def delete_firmware(%Firmware{} = firmware) do
    do_delete_firmware = fn ->
      firmware
      |> Firmware.delete_changeset(%{})
      |> Repo.delete()
    end

    do_delete_from_s3 = fn ->
      firmware.upload_metadata
      |> NervesHub.Workers.DeleteFirmware.new()
      |> Oban.insert()
    end

    Repo.transaction(fn ->
      with {:ok, firmware} <- do_delete_firmware.(),
           {:ok, _} <- do_delete_from_s3.() do
        {:ok, firmware}
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  @spec verify_signature(String.t(), [OrgKey.t()]) ::
          {:ok, OrgKey.t()}
          | {:error, :invalid_signature}
          | {:error, :no_public_keys}
  def verify_signature(_filepath, []), do: {:error, :no_public_keys}

  def verify_signature(filepath, keys) when is_binary(filepath) do
    signed_key =
      Enum.find(keys, fn %{key: key} ->
        case System.cmd("fwup", ["--verify", "--public-key", key, "-i", filepath]) do
          {_, 0} ->
            true

          # fwup returns a 1 for invalid signatures
          {_, 1} ->
            false

          {text, code} ->
            Logger.warning("fwup returned code #{code} with #{text}")

            false
        end
      end)

    case signed_key do
      %OrgKey{} = key ->
        {:ok, key}

      nil ->
        {:error, :invalid_signature}
    end
  end

  @doc """
  Returns metadata for a Firmware struct
  """
  @spec metadata_from_firmware(Firmware.t()) :: {:ok, FirmwareMetadata.metadata()}
  def metadata_from_firmware(%Firmware{} = firmware) do
    firmware = Repo.preload(firmware, [:product])

    metadata = %{
      architecture: firmware.architecture,
      author: firmware.author,
      description: firmware.description,
      misc: firmware.misc,
      platform: firmware.platform,
      product: firmware.product.name,
      uuid: firmware.uuid,
      vcs_identifier: firmware.vcs_identifier,
      version: firmware.version
    }

    {:ok, metadata}
  end

  @doc """
  Same as `metadata_from_firmware/1` but takes a file path instead of a firmware struct
  """
  @spec metadata_from_fwup(Path.t()) :: {:ok, FirmwareMetadata.metadata()} | {:error, any()}
  def metadata_from_fwup(firmware_file) do
    with {:ok, fwup_metadata} <- get_fwup_metadata(firmware_file),
         {:ok, uuid} <- fetch_fwup_metadata_value(fwup_metadata, "meta-uuid"),
         {:ok, architecture} <- fetch_fwup_metadata_value(fwup_metadata, "meta-architecture"),
         {:ok, platform} <- fetch_fwup_metadata_value(fwup_metadata, "meta-platform"),
         {:ok, product} <- fetch_fwup_metadata_value(fwup_metadata, "meta-product"),
         {:ok, version} <- fetch_fwup_metadata_value(fwup_metadata, "meta-version"),
         author <- get_fwup_metadata_value(fwup_metadata, "meta-author"),
         description <- get_fwup_metadata_value(fwup_metadata, "meta-description"),
         misc <- get_fwup_metadata_value(fwup_metadata, "meta-misc"),
         vcs_identifier <- get_fwup_metadata_value(fwup_metadata, "meta-vcs-identifier") do
      metadata = %{
        architecture: architecture,
        author: author,
        description: description,
        misc: misc,
        platform: platform,
        product: product,
        uuid: uuid,
        vcs_identifier: vcs_identifier,
        version: version
      }

      {:ok, metadata}
    end
  end

  def metadata_from_device(metadata) do
    params = %{
      uuid: Map.get(metadata, "nerves_fw_uuid"),
      architecture: Map.get(metadata, "nerves_fw_architecture"),
      platform: Map.get(metadata, "nerves_fw_platform"),
      product: Map.get(metadata, "nerves_fw_product"),
      version: Map.get(metadata, "nerves_fw_version"),
      author: Map.get(metadata, "nerves_fw_author"),
      description: Map.get(metadata, "nerves_fw_description"),
      fwup_version: Map.get(metadata, "fwup_version"),
      vcs_identifier: Map.get(metadata, "nerves_fw_vcs_identifier"),
      misc: Map.get(metadata, "nerves_fw_misc")
    }

    metadata_or_firmware(params)
  end

  def create_firmware_transfer(params) do
    %FirmwareTransfer{}
    |> FirmwareTransfer.changeset(params)
    |> Repo.insert()
  end

  @spec get_firmware_delta(integer()) ::
          {:ok, FirmwareDelta.t()}
          | {:error, :not_found}

  def get_firmware_delta(firmware_delta_id) do
    case Repo.get(FirmwareDelta, firmware_delta_id) do
      nil -> {:error, :not_found}
      firmware_delta -> {:ok, firmware_delta}
    end
  end

  @spec get_firmware_delta_by_source_and_target(Firmware.t(), Firmware.t()) ::
          {:ok, FirmwareDelta.t()}
          | {:error, :not_found}
  def get_firmware_delta_by_source_and_target(%Firmware{id: source_id}, %Firmware{id: target_id}) do
    get_firmware_delta_by_source_and_target(source_id, target_id)
  end

  @spec get_firmware_delta_by_source_and_target(integer(), integer()) ::
          {:ok, FirmwareDelta.t()}
          | {:error, :not_found}
  def get_firmware_delta_by_source_and_target(source_id, target_id) do
    FirmwareDelta
    |> where([fd], source_id: ^source_id)
    |> where([fd], target_id: ^target_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      firmware_delta -> {:ok, firmware_delta}
    end
  end

  @spec get_firmware_url(Firmware.t() | FirmwareDelta.t()) ::
          {:ok, String.t()}
          | {:error, :failure}
  def get_firmware_url(fw_or_delta) do
    firmware_upload_config().download_file(fw_or_delta)
  end

  @spec create_firmware_delta(Firmware.t(), Firmware.t()) ::
          {:ok, FirmwareDelta.t()}
          | {:error, Changeset.t()}

  def create_firmware_delta(source_firmware, target_firmware) do
    %Firmware{org: org} = source_firmware |> Repo.preload(:org)
    {:ok, source_url} = firmware_upload_config().download_file(source_firmware)
    {:ok, target_url} = firmware_upload_config().download_file(target_firmware)

    firmware_delta_path = delta_updater().create_firmware_delta_file(source_url, target_url)
    firmware_delta_filename = Path.basename(firmware_delta_path)

    Repo.transaction(
      fn ->
        with upload_metadata <-
               firmware_upload_config().metadata(org.id, firmware_delta_filename),
             {:ok, firmware_delta} <-
               insert_firmware_delta(%{
                 source_id: source_firmware.id,
                 target_id: target_firmware.id,
                 upload_metadata: upload_metadata
               }),
             {:ok, firmware_delta} <- get_firmware_delta(firmware_delta.id),
             :ok <- firmware_upload_config().upload_file(firmware_delta_path, upload_metadata),
             :ok <- delta_updater().cleanup_firmware_delta_files(firmware_delta_path) do
          firmware_delta
        else
          {:error, error} ->
            delta_updater().cleanup_firmware_delta_files(firmware_delta_path)
            Repo.rollback(error)
        end
      end,
      timeout: 30_000
    )
  end

  # Private functions

  defp with_product(query) do
    query
    |> join(:left, [f], p in assoc(f, :product))
    |> preload([d, p], product: p)
  end

  def insert_firmware_delta(params) do
    %FirmwareDelta{}
    |> FirmwareDelta.changeset(params)
    |> Repo.insert()
  end

  defp insert_firmware(params) do
    %Firmware{}
    |> Firmware.create_changeset(params)
    |> Repo.insert()
  end

  @spec build_firmware_params(Org.t(), Path.t()) :: {:ok, map()} | {:error, any()}
  defp build_firmware_params(%{id: org_id} = org, filepath) do
    org = NervesHub.Repo.preload(org, :org_keys)

    with {:ok, %{id: org_key_id}} <- verify_signature(filepath, org.org_keys),
         {:ok, metadata} <- metadata_from_fwup(filepath) do
      filename = metadata.uuid <> ".fw"

      params =
        resolve_product(%{
          architecture: metadata.architecture,
          author: metadata.author,
          description: metadata.description,
          filename: filename,
          filepath: filepath,
          misc: metadata.misc,
          org_id: org_id,
          org_key_id: org_key_id,
          delta_updatable: delta_updater().delta_updatable?(filepath),
          platform: metadata.platform,
          product_name: metadata.product,
          upload_metadata: firmware_upload_config().metadata(org_id, filename),
          size: :filelib.file_size(filepath),
          uuid: metadata.uuid,
          vcs_identifier: metadata.vcs_identifier,
          version: metadata.version
        })

      {:ok, params}
    end
  end

  defp resolve_product(params) do
    with {:ok, product} <-
           Products.get_product_by_org_id_and_name(params.org_id, params.product_name) do
      Map.put(params, :product_id, product.id)
    else
      _ -> params
    end
  end

  @spec metadata_or_firmware(map()) :: {:ok, FirmwareMetadata.t() | nil}
  def metadata_or_firmware(metadata) do
    case FirmwareMetadata.changeset(%FirmwareMetadata{}, metadata).valid? do
      true ->
        {:ok, metadata}

      false ->
        case Map.get(metadata, :uuid) do
          nil ->
            {:ok, nil}

          uuid ->
            case get_firmware_by_uuid(uuid) do
              nil ->
                {:ok, nil}

              firmware ->
                metadata_from_firmware(firmware)
            end
        end
    end
  end

  @typep metadata_string() :: String.t()
  @typep metadata_key() :: String.t()
  @typep metadata_value() :: String.t() | nil

  @spec get_fwup_metadata(Path.t()) :: {:ok, metadata_string()} | {:error, String.t()}
  defp get_fwup_metadata(filepath) do
    case System.cmd("fwup", ["-m", "-i", filepath]) do
      {metadata, 0} ->
        {:ok, metadata}

      {error, _} ->
        {:error, error}
    end
  end

  @spec fetch_fwup_metadata_value(metadata_string(), metadata_key()) ::
          {:ok, metadata_value()} | {:error, {metadata_key(), :not_found}}
  defp fetch_fwup_metadata_value(metadata, key) when is_binary(key) do
    {:ok, regex} = "#{key}=\"(?<value>[^\n]+)\"" |> Regex.compile()

    case Regex.named_captures(regex, metadata) do
      %{"value" => value} -> {:ok, value}
      _ -> {:error, {key, :not_found}}
    end
  end

  @spec get_fwup_metadata_value(metadata_string(), metadata_key()) :: metadata_value()
  defp get_fwup_metadata_value(metadata, key) when is_binary(key) do
    case fetch_fwup_metadata_value(metadata, key) do
      {:ok, metadata_item} -> metadata_item
      {:error, {_, :not_found}} -> nil
    end
  end

  defp delta_updater() do
    Application.get_env(
      :nerves_hub,
      :delta_updater,
      NervesHub.Firmwares.DeltaUpdater.Default
    )
  end
end
