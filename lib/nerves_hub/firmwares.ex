defmodule NervesHub.Firmwares do
  import Ecto.Query

  alias Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Firmwares.FirmwareTransfer
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Workers.DeleteFirmware
  alias NervesHub.Workers.FirmwareDeltaBuilder

  alias NervesHub.Repo

  require Logger

  @type upload_file_2 :: (filepath :: String.t(), filename :: String.t() -> :ok | {:error, any()})

  defp firmware_upload_config(), do: Application.fetch_env!(:nerves_hub, :firmware_upload)

  @spec get_deltas_by_target_firmware(firmware :: Firmware.t()) :: [FirmwareDelta.t()]
  def get_deltas_by_target_firmware(firmware) do
    FirmwareDelta
    |> where([fd], fd.target_id == ^firmware.id)
    |> preload(:source)
    |> preload(:target)
    |> Repo.all()
  end

  @spec count(Product.t()) :: non_neg_integer()
  def count(product) do
    Firmware
    |> where([f], f.product_id == ^product.id)
    |> Repo.aggregate(:count)
  end

  @spec get_unique_platforms(Product.t()) :: [String.t()]
  def get_unique_platforms(product) do
    Firmware
    |> select([f], f.platform)
    |> distinct(true)
    |> where([f], f.product_id == ^product.id)
    |> Repo.all()
  end

  @spec get_unique_architectures(Product.t()) :: [String.t()]
  def get_unique_architectures(product) do
    Firmware
    |> select([f], f.architecture)
    |> distinct(true)
    |> where([f], f.product_id == ^product.id)
    |> Repo.all()
  end

  @spec get_firmwares_by_product(integer()) :: [Firmware.t()]
  def get_firmwares_by_product(product_id) do
    Firmware
    |> where([f], f.product_id == ^product_id)
    |> order_by([f], [fragment("? collate numeric desc", f.version), desc: :inserted_at])
    |> with_product()
    |> Repo.all()
  end

  @spec get_firmwares(Product.t(), String.t(), String.t()) :: [Firmware.t()]
  def get_firmwares(product, platform, architecture) do
    Firmware
    |> where([f], f.product_id == ^product.id)
    |> where([f], f.platform == ^platform)
    |> where([f], f.architecture == ^architecture)
    |> order_by([f], [fragment("? collate numeric desc", f.version), desc: :inserted_at])
    |> limit(25)
    |> Repo.all()
  end

  @spec filter(Product.t(), map()) :: {[Product.t()], Flop.Meta.t()}
  def filter(product, opts \\ %{}) do
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) end)

    sort = Map.get(opts, :sort, "inserted_at")
    sort_direction = Map.get(opts, :sort_direction, "desc")

    sort_opts = {String.to_existing_atom(sort_direction), String.to_atom(sort)}

    flop = %Flop{
      page: String.to_integer(Map.get(opts, :page, "1")),
      page_size: String.to_integer(Map.get(opts, :page_size, "25"))
    }

    subquery =
      Device
      |> select([d], %{
        firmware_uuid: fragment("? ->> 'uuid'", d.firmware_metadata),
        install_count: count(fragment("? ->> 'uuid'", d.firmware_metadata))
      })
      |> where([d], not is_nil(d.firmware_metadata))
      |> where([d], not is_nil(fragment("? ->> 'uuid'", d.firmware_metadata)))
      |> Repo.exclude_deleted()
      |> group_by([d], fragment("? ->> 'uuid'", d.firmware_metadata))

    Firmware
    |> join(:left, [f], d in subquery(subquery), on: d.firmware_uuid == f.uuid)
    |> where([f], f.product_id == ^product.id)
    |> sort_firmware(sort_opts)
    |> select_merge([_f, d], %{install_count: d.install_count})
    |> Flop.run(flop)
  end

  defp sort_firmware(query, {direction, :install_count}) do
    order_by(query, [_f, d], {^direction, d.install_count})
  end

  defp sort_firmware(query, sort), do: order_by(query, ^sort)

  def get_firmwares_for_deployment_group(deployment_group) do
    deployment_group = Repo.preload(deployment_group, [:firmware])

    Firmware
    |> where([f], f.product_id == ^deployment_group.product_id)
    |> where([f], f.platform == ^deployment_group.firmware.platform)
    |> where([f], f.architecture == ^deployment_group.firmware.architecture)
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
  def get_firmware(_, nil) do
    {:error, :not_found}
  end

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

  @spec get_firmware_by_product_id_and_uuid(integer(), String.t()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware_by_product_id_and_uuid(product_id, uuid) do
    get_firmware_by_product_and_uuid_query(%Product{id: product_id}, uuid)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      firmware -> {:ok, firmware}
    end
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
      timeout: 60_000
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
      |> DeleteFirmware.new()
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
        case System.cmd("fwup", ["--verify", "--public-key", key, "-i", filepath], env: []) do
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

  @spec metadata_from_device(map()) :: {:ok, FirmwareMetadata.t() | nil}
  def metadata_from_device(metadata) do
    metadata = %{
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
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.all()
    |> case do
      [] -> {:error, :not_found}
      [firmware_delta] -> {:ok, firmware_delta}
    end
  end

  @spec get_firmware_url(Firmware.t() | FirmwareDelta.t()) ::
          {:ok, String.t()}
          | {:error, :failure}
  def get_firmware_url(fw_or_delta) do
    firmware_upload_config().download_file(fw_or_delta)
  end

  @spec generate_firmware_delta(FirmwareDelta.t(), Firmware.t(), Firmware.t()) ::
          :ok
          | {:error, Changeset.t()}

  def generate_firmware_delta(firmware_delta, source_firmware, target_firmware) do
    Logger.info("Creating firmware delta between #{source_firmware.uuid} and #{target_firmware.uuid}.")

    %Firmware{org: org} = source_firmware |> Repo.preload(:org)
    {:ok, source_url} = firmware_upload_config().download_file(source_firmware)
    {:ok, target_url} = firmware_upload_config().download_file(target_firmware)

    case update_tool().create_firmware_delta_file(
           {source_firmware.uuid, source_url},
           {target_firmware.uuid, target_url}
         ) do
      {:ok, created} ->
        Repo.transact(
          fn ->
            upload_metadata =
              firmware_upload_config().delta_metadata(
                org.id,
                source_firmware.uuid,
                target_firmware.uuid
              )

            with {:ok, firmware_delta} <-
                   complete_firmware_delta(
                     firmware_delta,
                     created.tool,
                     created.size,
                     created.source_size,
                     created.target_size,
                     created.tool_metadata,
                     upload_metadata
                   ),
                 {:ok, firmware_delta} <- get_firmware_delta(firmware_delta.id),
                 :ok <-
                   firmware_upload_config().upload_file(created.filepath, upload_metadata),
                 :ok <- update_tool().cleanup_firmware_delta_files(created.filepath) do
              Logger.info(
                "Created firmware delta successfully.",
                product_id: source_firmware.product_id,
                source_firmware: source_firmware.uuid,
                target_firmware: target_firmware.uuid
              )

              {:ok, firmware_delta}
            else
              {:error, error} ->
                update_tool().cleanup_firmware_delta_files(created.filepath)

                Logger.error(
                  "Failed to create firmware delta: #{inspect(error)}",
                  product_id: source_firmware.product_id,
                  source_firmware: source_firmware.uuid,
                  target_firmware: target_firmware.uuid
                )

                {:error, error}
            end
          end,
          timeout: 30_000
        )
        |> case do
          {:ok, _delta} ->
            :ok

          {:error, err} ->
            _ = fail_firmware_delta(firmware_delta)
            {:error, err}
        end

      {:error, :no_delta_support_in_firmware} ->
        Logger.info(
          "Delta generation failed gracefully. There were no markers for delta generation.",
          product_id: source_firmware.product_id,
          source_firmware: source_firmware.uuid,
          target_firmware: target_firmware.uuid
        )

        :ok

      # We log the issue in the update tool, so no need to here
      {:error, :delta_not_created} ->
        :ok
    end
  end

  # Private functions

  defp with_product(query) do
    query
    |> join(:left, [f], p in assoc(f, :product))
    |> preload([d, p], product: p)
  end

  @spec attempt_firmware_delta(
          source_id :: non_neg_integer(),
          target_id :: non_neg_integer()
        ) :: {:ok, FirmwareDelta.t()} | {:error, Ecto.Changeset.t()}
  def attempt_firmware_delta(source_id, target_id) do
    Repo.transaction(fn ->
      with {:error, :not_found} <- get_firmware_delta_by_source_and_target(source_id, target_id),
           {:ok, firmware_delta} <- start_firmware_delta(source_id, target_id) do
        FirmwareDeltaBuilder.start(source_id, target_id)
        firmware_delta
      end
    end)
  end

  @spec start_firmware_delta(
          source :: Firmware.t() | non_neg_integer(),
          target :: Firmware.t() | non_neg_integer()
        ) :: {:ok, FirmwareDelta.t()} | {:error, Ecto.Changeset.t()}
  def start_firmware_delta(%Firmware{id: source_id}, %Firmware{id: target_id}) do
    start_firmware_delta(source_id, target_id)
  end

  def start_firmware_delta(source_id, target_id) do
    FirmwareDelta.start_changeset(source_id, target_id)
    |> Repo.insert()
  end

  @spec complete_firmware_delta(
          firmware_delta :: FirmwareDelta.t(),
          tool :: String.t(),
          size :: non_neg_integer(),
          source_size :: non_neg_integer(),
          target_size :: non_neg_integer(),
          tool_metadata :: map(),
          upload_metadata :: map()
        ) :: {:ok, FirmwareDelta.t()} | {:error, Ecto.Changeset.t()}
  def complete_firmware_delta(
        %FirmwareDelta{} = firmware_delta,
        tool,
        size,
        source_size,
        target_size,
        tool_metadata,
        upload_metadata
      ) do
    firmware_delta
    |> FirmwareDelta.complete_changeset(
      tool,
      size,
      source_size,
      target_size,
      tool_metadata,
      upload_metadata
    )
    |> Repo.update()
  end

  @spec fail_firmware_delta(FirmwareDelta.t()) ::
          {:ok, FirmwareDelta.t()} | {:error, Ecto.Changeset.t()}
  def fail_firmware_delta(%FirmwareDelta{} = firmware_delta) do
    firmware_delta
    |> FirmwareDelta.fail_changeset()
    |> Repo.update()
  end

  @spec time_out_firmware_delta(FirmwareDelta.t()) ::
          {:ok, FirmwareDelta.t()} | {:error, Ecto.Changeset.t()}
  def time_out_firmware_delta(%FirmwareDelta{} = firmware_delta) do
    firmware_delta
    |> FirmwareDelta.time_out_changeset()
    |> Repo.update()
  end

  def insert_firmware_delta(params) do
    %FirmwareDelta{}
    |> FirmwareDelta.create_changeset(params)
    |> Repo.insert()
  end

  defp insert_firmware(params) do
    %Firmware{}
    |> Firmware.create_changeset(params)
    |> Repo.insert()
  end

  @spec refresh_firmware_tool_metadata(Firmware.t()) :: :ok | {:error, any()}
  def refresh_firmware_tool_metadata(firmware) do
    case update_tool().get_firmware_metadata_from_upload(firmware) do
      {:ok, %{tool_metadata: tm}} ->
        firmware
        |> Firmware.update_changeset(%{tool_metadata: tm})
        |> Repo.update()

      err ->
        err
    end
  end

  @spec time_out_firmware_delta_generations(
          age :: non_neg_integer(),
          unit :: :second | :millisecond | :minute
        ) ::
          :ok | {:error, any()}
  def time_out_firmware_delta_generations(age_seconds, unit) do
    cutoff = DateTime.add(DateTime.utc_now(), -age_seconds, unit)

    from(fd in FirmwareDelta,
      where: fd.status == :processing,
      where: fd.inserted_at < ^cutoff
    )
    |> Repo.update_all(set: [status: :timed_out])
  end

  @spec build_firmware_params(Org.t(), Path.t()) :: {:ok, map()} | {:error, any()}
  defp build_firmware_params(%{id: org_id} = org, filepath) do
    org = NervesHub.Repo.preload(org, :org_keys)

    with {:ok, %{id: org_key_id}} <- verify_signature(filepath, org.org_keys),
         {:ok, %{path: conf_path, firmware_metadata: fm, tool_metadata: tm} = m} <-
           update_tool().get_firmware_metadata_from_file(filepath) do
      filename = fm.uuid <> ".fw"

      params =
        resolve_product(%{
          architecture: fm.architecture,
          author: fm.author,
          description: fm.description,
          filename: filename,
          filepath: filepath,
          misc: fm.misc,
          org_id: org_id,
          org_key_id: org_key_id,
          delta_updatable: update_tool().delta_updatable?(conf_path),
          platform: fm.platform,
          product_name: fm.product,
          upload_metadata: firmware_upload_config().metadata(org_id, filename),
          size: :filelib.file_size(filepath),
          tool: m.tool,
          tool_delta_required_version: m.tool_delta_required_version,
          tool_full_required_version: m.tool_full_required_version,
          uuid: fm.uuid,
          vcs_identifier: fm.vcs_identifier,
          version: fm.version,
          tool_metadata: tm
        })

      {:ok, params}
    end
  end

  defp resolve_product(params) do
    case Products.get_product_by_org_id_and_name(params.org_id, params.product_name) do
      {:ok, product} ->
        Map.put(params, :product_id, product.id)

      _ ->
        params
    end
  end

  defp update_tool() do
    Application.get_env(
      :nerves_hub,
      :update_tool,
      # Fall back to old config key
      Application.get_env(:nerves_hub, :delta_updater, NervesHub.Firmwares.UpdateTool.Fwup)
    )
  end
end
