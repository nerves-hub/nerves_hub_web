defmodule NervesHubWebCore.Firmwares do
  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Accounts.{OrgKey, Org}
  alias NervesHubWebCore.Firmwares.{Firmware, FirmwareMetadata, FirmwareDelta, FirmwareTransfer}
  alias NervesHubWebCore.Products
  alias NervesHubWebCore.Products.Product
  alias NervesHubWebCore.Repo

  require Logger

  @min_fwup_delta_updatable_version ">=1.6.0"

  @type upload_file_2 :: (filepath :: String.t(), filename :: String.t() -> :ok | {:error, any()})

  @uploader Application.fetch_env!(:nerves_hub_web_core, :firmware_upload)

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

  def get_firmware!(firmware_id), do: Repo.get!(Firmware, firmware_id)

  @spec get_firmware_by_org_id(non_neg_integer()) :: [Firmware.t()]
  def get_firmware_by_org_id(org_id) do
    q =
      from(
        f in Firmware,
        join: p in assoc(f, :product),
        where: p.org_id == ^org_id
      )

    Repo.all(q)
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

  @spec get_firmware_by_uuid(String.t()) :: [Firmware.t()]
  def get_firmware_by_uuid(uuid) do
    from(
      f in Firmware,
      where: f.uuid == ^uuid
    )
    |> Repo.all()
  end

  @spec get_firmware_by_product_and_uuid(Product.t(), String.t()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware_by_product_and_uuid(%Product{id: product_id}, uuid) do
    from(
      f in Firmware,
      where: f.uuid == ^uuid,
      join: p in assoc(f, :product),
      preload: [product: p],
      where: p.id == ^product_id
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      firmware -> {:ok, firmware}
    end
  end

  @spec create_firmware(Org.t(), String.t(), opts :: [{:upload_file_2, upload_file_2()}]) ::
          {:ok, Firmware.t()}
          | {:error, Changeset.t() | :no_public_keys | :invalid_signature | any}
  def create_firmware(org, filepath, params \\ %{}, opts \\ []) do
    upload_file_2 = opts[:upload_file_2] || (&@uploader.upload_file/2)

    Repo.transaction(
      fn ->
        with {:ok, params} <- build_firmware_params(org, filepath, params),
             params <- set_ttl(org, params),
             {:ok, firmware} <- insert_firmware(params),
             :ok <- upload_file_2.(filepath, firmware.upload_metadata) do
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
    Repo.transaction(fn ->
      with {:ok, _} <- firmware |> Firmware.delete_changeset(%{}) |> Repo.delete(),
           :ok <- @uploader.delete_file(firmware) do
        :ok
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, _} -> :ok
      ret -> ret
    end
  end

  @spec verify_signature(String.t(), [OrgKey.t()]) ::
          {:ok, OrgKey.t()}
          | {:error, :invalid_signature}
          | {:error, :no_public_keys}
  def verify_signature(_filepath, []), do: {:error, :no_public_keys}

  def verify_signature(filepath, keys) when is_binary(filepath) do
    keys
    |> Enum.find(fn %{key: key} ->
      case System.cmd("fwup", ["--verify", "--public-key", key, "-i", filepath]) do
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

  def update_firmware_ttl(nil), do: :ok

  def update_firmware_ttl(firmware_id) do
    q =
      from(f in NervesHubWebCore.Firmwares.Firmware,
        left_join: d in NervesHubWebCore.Deployments.Deployment,
        on: d.firmware_id == f.id,
        where:
          f.id == ^firmware_id and
            not is_nil(d.firmware_id),
        limit: 1
      )

    case Repo.one(q) do
      # Firmware has no associations. Set ttl.
      nil ->
        case NervesHubWebCore.Repo.get(Firmware, firmware_id) do
          %Firmware{ttl_until: nil, ttl: ttl} = firmware ->
            ttl_until = DateTime.utc_now() |> Timex.shift(seconds: ttl)

            firmware
            |> Firmware.update_changeset(%{ttl_until: ttl_until})
            |> Repo.update()

            :set

          _ ->
            :noop
        end

      # Firmware has associations and no ttl has been set.
      %Firmware{ttl_until: nil} ->
        :noop

      # Firmware has associations and is marked for ttl. Unset ttl.
      %Firmware{} = firmware ->
        firmware
        |> Firmware.update_changeset(%{ttl_until: nil})
        |> Repo.update()

        :unset
    end
  end

  def get_firmware_by_expired_ttl() do
    from(
      f in Firmware,
      where: f.ttl_until < ^DateTime.utc_now()
    )
    |> Repo.all()
  end

  def metadata_from_conn(%Plug.Conn{} = conn) do
    params = %{
      uuid: get_metadata_req_header(conn, "uuid"),
      architecture: get_metadata_req_header(conn, "architecture"),
      platform: get_metadata_req_header(conn, "platform"),
      product: get_metadata_req_header(conn, "product"),
      version: get_metadata_req_header(conn, "version"),
      author: get_metadata_req_header(conn, "author"),
      description: get_metadata_req_header(conn, "description"),
      fwup_version: get_metadata_req_header(conn, "fwup-version"),
      vcs_identifier: get_metadata_req_header(conn, "vcs-identifier"),
      misc: get_metadata_req_header(conn, "misc")
    }

    metadata_or_firmware(params)
  end

  def metadata_from_firmware(%Firmware{} = firmware) do
    firmware = Repo.preload(firmware, [:product])

    metadata = %{
      uuid: firmware.uuid,
      architecture: firmware.architecture,
      platform: firmware.platform,
      product: firmware.product.name,
      version: firmware.version,
      author: firmware.author,
      description: firmware.description,
      vcs_identifier: firmware.vcs_identifier,
      misc: firmware.misc
    }

    {:ok, metadata}
  end

  def metadata_from_fwup(firmware_file) do
    with {:ok, fwup_metadata} <- get_fwup_metadata(firmware_file),
         {:ok, uuid} <- fetch_fwup_metadata_item(fwup_metadata, "meta-uuid"),
         {:ok, architecture} <- fetch_fwup_metadata_item(fwup_metadata, "meta-architecture"),
         {:ok, platform} <- fetch_fwup_metadata_item(fwup_metadata, "meta-platform"),
         {:ok, product} <- fetch_fwup_metadata_item(fwup_metadata, "meta-product"),
         {:ok, version} <- fetch_fwup_metadata_item(fwup_metadata, "meta-version"),
         author <- get_fwup_metadata_item(fwup_metadata, "meta-author"),
         description <- get_fwup_metadata_item(fwup_metadata, "meta-description"),
         misc <- get_fwup_metadata_item(fwup_metadata, "meta-misc"),
         vcs_identifier <- get_fwup_metadata_item(fwup_metadata, "meta-vcs-identifier") do
      metadata = %{
        uuid: uuid,
        architecture: architecture,
        platform: platform,
        product: product,
        version: version,
        author: author,
        description: description,
        vcs_identifier: vcs_identifier,
        misc: misc
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

  def get_firmware_transfers_by_org_id_between_dates(org_id, from_datetime, to_datetime) do
    q =
      from(
        ft in FirmwareTransfer,
        where:
          ft.org_id == ^org_id and
            ft.timestamp >= ^from_datetime and
            ft.timestamp <= ^to_datetime
      )

    Repo.all(q)
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
    q =
      from(
        fp in FirmwareDelta,
        where:
          fp.source_id == ^source_id and
            fp.target_id >= ^target_id
      )

    case Repo.one(q) do
      nil -> {:error, :not_found}
      firmware_delta -> {:ok, firmware_delta}
    end
  end

  @spec get_firmware_url(Firmware.t(), Firmware.t(), String.t(), Product.t()) ::
          {:ok, String.t()}
          | {:error, :failure}

  def get_firmware_url(source, target, fwup_version, %Product{delta_updatable: true})
      when is_binary(fwup_version) do
    if Version.match?(fwup_version, @min_fwup_delta_updatable_version) do
      do_get_firmware_url(source, target)
    else
      @uploader.download_file(target)
    end
  end

  def get_firmware_url(_source, target, _fwup_version, _product),
    do: @uploader.download_file(target)

  @spec create_firmware_delta(Firmware.t(), Firmware.t()) ::
          {:ok, FirmwareDelta.t()}
          | {:error, Changeset.t()}

  def create_firmware_delta(source_firmware, target_firmware) do
    %Firmware{org: org} = source_firmware |> Repo.preload(:org)
    {:ok, source_url} = @uploader.download_file(source_firmware)
    {:ok, target_url} = @uploader.download_file(target_firmware)

    firmware_delta_path = delta_updater().create_firmware_delta_file(source_url, target_url)
    firmware_delta_filename = Path.basename(firmware_delta_path)

    Repo.transaction(
      fn ->
        with upload_metadata <- @uploader.metadata(org.id, firmware_delta_filename),
             {:ok, firmware_delta} <-
               insert_firmware_delta(%{
                 source_id: source_firmware.id,
                 target_id: target_firmware.id,
                 upload_metadata: upload_metadata
               }),
             {:ok, firmware_delta} <- get_firmware_delta(firmware_delta.id),
             :ok <- @uploader.upload_file(firmware_delta_path, upload_metadata),
             :ok <- delta_updater().cleanup_firmware_delta_files(firmware_delta_path) do
          firmware_delta
        else
          {:error, error} ->
            Repo.rollback(error)
        end
      end,
      timeout: 30_000
    )
  end

  # Private functions

  def insert_firmware_delta(params) do
    %FirmwareDelta{}
    |> FirmwareDelta.changeset(params)
    |> Repo.insert()
  end

  defp do_get_firmware_url(
         %Firmware{delta_updatable: true} = source,
         %Firmware{delta_updatable: true} = target
       ) do
    {:ok, firmware_delta} =
      case get_firmware_delta_by_source_and_target(source, target) do
        {:error, :not_found} -> create_firmware_delta(source, target)
        firmware_delta -> firmware_delta
      end

    @uploader.download_file(firmware_delta)
  end

  defp do_get_firmware_url(_, target), do: @uploader.download_file(target)

  defp insert_firmware(params) do
    %Firmware{}
    |> Firmware.create_changeset(params)
    |> Repo.insert()
  end

  defp build_firmware_params(%{id: org_id} = org, filepath, params) do
    org = NervesHubWebCore.Repo.preload(org, :org_keys)

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
          upload_metadata: @uploader.metadata(org_id, filename),
          size: :filelib.file_size(filepath),
          ttl: Map.get(params, :ttl),
          uuid: metadata.uuid,
          vcs_identifier: metadata.vcs_identifier,
          version: metadata.version
        })

      {:ok, params}
    end
  end

  defp set_ttl(%{id: org_id}, params) do
    ttl =
      case Map.get(params, :ttl) do
        ttl when ttl == nil or ttl == "" ->
          org_id
          |> Accounts.get_org_limit_by_org_id()
          |> Map.get(:firmware_ttl_seconds_default)

        ttl when is_binary(ttl) ->
          String.to_integer(ttl)

        ttl ->
          ttl
      end

    ttl_until = DateTime.utc_now() |> Timex.shift(seconds: ttl)

    params
    |> Map.put(:ttl, ttl)
    |> Map.put(:ttl_until, ttl_until)
  end

  defp resolve_product(params) do
    params.org_id
    |> Products.get_product_by_org_id_and_name(params.product_name)
    |> case do
      {:ok, product} -> Map.put(params, :product_id, product.id)
      _ -> params
    end

    with {:ok, product} <-
           Products.get_product_by_org_id_and_name(params.org_id, params.product_name) do
      Map.put(params, :product_id, product.id)
    else
      _ -> params
    end
  end

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
              [firmware | _] -> metadata_from_firmware(firmware)
              [] -> {:ok, nil}
            end
        end
    end
  end

  defp get_fwup_metadata(filepath) do
    case System.cmd("fwup", ["-m", "-i", filepath]) do
      {metadata, 0} ->
        {:ok, metadata}

      _error ->
        {:error}
    end
  end

  @spec fetch_fwup_metadata_item(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, {String.t(), :not_found}}
  defp fetch_fwup_metadata_item(metadata, key) when is_binary(key) do
    {:ok, regex} = "#{key}=\"(?<item>[^\n]+)\"" |> Regex.compile()

    case Regex.named_captures(regex, metadata) do
      %{"item" => item} -> {:ok, item}
      _ -> {:error, {key, :not_found}}
    end
  end

  @spec get_fwup_metadata_item(String.t(), String.t(), String.t() | nil) :: String.t() | nil
  defp get_fwup_metadata_item(metadata, key, default \\ nil) when is_binary(key) do
    case fetch_fwup_metadata_item(metadata, key) do
      {:ok, metadata_item} -> metadata_item
      {:error, {_, :not_found}} -> default
    end
  end

  defp get_metadata_req_header(conn, header) do
    case Plug.Conn.get_req_header(conn, "x-nerveshub-#{header}") do
      [] -> nil
      ["" | _] -> nil
      [value | _] -> value
    end
  end

  defp delta_updater() do
    Application.get_env(
      :nerves_hub_web_core,
      :delta_updater,
      NervesHubWebCore.Firmwares.DeltaUpdater.Default
    )
  end
end
