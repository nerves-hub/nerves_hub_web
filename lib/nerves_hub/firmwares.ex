defmodule NervesHub.Firmwares do
  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Accounts.Scope
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Firmwares.FirmwareTransfer
  alias NervesHub.Firmwares.UpdateTool.Fwup
  alias NervesHub.Helpers.Logging
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Workers.DeleteFirmware
  alias NervesHub.Workers.FirmwareDeltaBuilder
  alias Phoenix.Socket.Broadcast

  require Logger

  @firmware_partial_chunk_size 1024 * 1024

  @type upload_file_2 :: (filepath :: String.t(), filename :: String.t() -> :ok | {:error, any()})

  defp firmware_upload_config(), do: Application.fetch_env!(:nerves_hub, :firmware_upload)

  @spec get_by_id(Product.t() | DeploymentGroup.t(), pos_integer()) :: Firmware.t() | nil
  def get_by_id(_product, firmware_id) when firmware_id in [nil, ""], do: nil

  def get_by_id(%DeploymentGroup{} = deployment_group, firmware_id) do
    Firmware
    |> where([f], f.platform == ^deployment_group.platform)
    |> where([f], f.architecture == ^deployment_group.architecture)
    |> where([f], f.product_id == ^deployment_group.product_id)
    |> where([f], f.id == ^firmware_id)
    |> Repo.one()
  end

  def get_by_id(%Product{} = product, firmware_id) do
    Firmware
    |> where([f], f.product_id == ^product.id)
    |> where([f], f.id == ^firmware_id)
    |> Repo.one()
  end

  def get_by_uuid(_product, nil), do: nil

  def get_by_uuid(%Product{} = product, uuid) do
    get_firmware_by_product_and_uuid_query(product, uuid)
    |> Repo.one()
  end

  @spec get_deltas_by_target_firmware(firmware :: Firmware.t()) :: [FirmwareDelta.t()]
  def get_deltas_by_target_firmware(%Firmware{id: firmware_id}) do
    FirmwareDelta
    |> where([fd], fd.target_id == ^firmware_id)
    |> join(:inner, [fd], fd in assoc(fd, :source))
    |> order_by([fd, s], fragment(~s|semver_sort_key(?) COLLATE "C" ASC NULLS LAST|, s.version))
    |> preload([fd, s], source: s)
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
    |> order_by_latest_version()
    |> with_product()
    |> Repo.all()
  end

  @spec get_firmwares_by_product_and_platform(Product.t(), String.t()) :: [Firmware.t()]
  def get_firmwares_by_product_and_platform(product, platform) do
    Firmware
    |> where([f], f.product_id == ^product.id)
    |> where([f], f.platform == ^platform)
    |> order_by_latest_version()
    |> limit(25)
    |> Repo.all()
  end

  @spec get_firmwares(Product.t(), String.t(), String.t()) :: [Firmware.t()]
  def get_firmwares(product, platform, architecture) do
    Firmware
    |> where([f], f.product_id == ^product.id)
    |> where([f], f.platform == ^platform)
    |> where([f], f.architecture == ^architecture)
    |> order_by_latest_version()
    |> limit(25)
    |> Repo.all()
  end

  @spec filter(Product.t(), map()) :: {[Product.t()], Flop.Meta.t()}
  def filter(product, opts \\ %{}) do
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) end)

    sort = Map.get(opts, :sort, "inserted_at")
    sort_direction = Map.get(opts, :sort_direction, "desc")

    sort_opts = {String.to_existing_atom(sort_direction), String.to_existing_atom(sort)}

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

  defp sort_firmware(query, {direction, :version}) do
    order_by(query, [f], [
      {^version_sort_direction(direction), fragment(~s|semver_sort_key(?) COLLATE "C"|, f.version)}
    ])
  end

  defp sort_firmware(query, sort), do: order_by(query, ^sort)

  # Orders a Firmware query by SemVer precedence, newest first, with invalid
  # versions (a NULL sort key) sorted last. Uses `semver_sort_key/1` under
  # `COLLATE "C"`: the key relies on plain byte ordering, and the database's
  # `en_US.utf8` default inverts pre-release/release order without it (see the
  # `add_semver_sort_key_function` migration).
  defp order_by_latest_version(query) do
    order_by(query, [f], [
      fragment(~s|semver_sort_key(?) COLLATE "C" DESC NULLS LAST|, f.version),
      desc: :inserted_at
    ])
  end

  defp version_sort_direction(:desc), do: :desc_nulls_last
  defp version_sort_direction(_), do: :asc_nulls_last

  def get_firmwares_for_deployment_group(deployment_group) do
    Firmware
    |> where([f], f.product_id == ^deployment_group.product_id)
    |> where([f], f.platform == ^deployment_group.platform)
    |> where([f], f.architecture == ^deployment_group.architecture)
    |> order_by_latest_version()
    |> with_product()
    |> Repo.all()
  end

  @doc """
  Get only version numbers for a product, sorted highest first
  """
  def get_firmware_versions_by_product(product_id) do
    Firmware
    |> where([f], f.product_id == ^product_id)
    |> select([f], %{version: f.version, sort_key: fragment(~s|semver_sort_key(?) COLLATE "C"|, f.version)})
    |> distinct(true)
    |> order_by([f], fragment(~s|semver_sort_key(?) COLLATE "C" DESC NULLS LAST|, f.version))
    |> Repo.all()
    |> Enum.map(& &1.version)
  end

  @doc """
  The product's firmwares as `%{version, uuid}` maps, newest version first.
  """
  def firmware_versions_and_uuids(product_id) do
    Firmware
    |> where([f], f.product_id == ^product_id)
    |> order_by_latest_version()
    |> select([f], %{version: f.version, uuid: f.uuid})
    |> Repo.all()
  end

  @spec get_firmware(Org.t() | Product.t(), integer()) ::
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
    |> Repo.fetch()
  end

  def get_firmware(%Product{id: product_id}, id) do
    Firmware
    |> where([f], f.id == ^id)
    |> where([f], f.product_id == ^product_id)
    |> Repo.fetch()
  end

  def get_firmware!(firmware_id), do: Repo.get!(Firmware, firmware_id)

  @doc """
  Preloads a firmware's product.
  """
  def preload_product(%Firmware{} = firmware), do: Repo.preload(firmware, :product)

  def get_firmware_for_device(%Device{firmware_metadata: nil}), do: []

  def get_firmware_for_device(device) do
    Firmware
    |> where([f], f.platform == ^device.firmware_metadata.platform)
    |> where([f], f.architecture == ^device.firmware_metadata.architecture)
    |> where([f], f.org_id == ^device.org_id)
    |> where([f], f.product_id == ^device.product_id)
    |> order_by_latest_version()
    |> Repo.all()
  end

  @spec get_firmware_by_org_id(non_neg_integer()) :: [Firmware.t()]
  def get_firmware_by_org_id(org_id) do
    Firmware
    |> with_product()
    |> where([f, p], p.org_id == ^org_id)
    |> Repo.all()
  end

  @spec get_firmware_by_product_id_and_uuid(integer(), String.t() | nil) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware_by_product_id_and_uuid(_product_id, nil) do
    {:error, :not_found}
  end

  def get_firmware_by_product_id_and_uuid(product_id, uuid) do
    get_firmware_by_product_and_uuid_query(%Product{id: product_id}, uuid)
    |> Repo.fetch()
  end

  @spec get_firmware_by_uuid(Scope.t(), String.t()) :: {:ok, Firmware.t()} | {:error, :not_found}
  def get_firmware_by_uuid(%Scope{} = scope, uuid) do
    get_firmware_by_product_and_uuid(scope.product, uuid)
  end

  @spec get_firmware_by_uuid!(Scope.t(), String.t()) :: Firmware.t()
  def get_firmware_by_uuid!(%Scope{} = scope, uuid) do
    get_firmware_by_product_and_uuid_query(scope.product, uuid)
    |> Repo.one!()
  end

  @spec get_firmware_by_product_and_uuid(Product.t(), String.t()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware_by_product_and_uuid(%Product{} = product, uuid) do
    get_firmware_by_product_and_uuid_query(product, uuid)
    |> Repo.fetch()
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
    upload_file_2 = opts[:upload_file_2] || (&firmware_upload_config().upload_file(&1, &2))

    Repo.transact(
      fn ->
        with {:ok, params} <- build_firmware_params(org, filepath),
             {:ok, firmware} <- insert_firmware(params),
             :ok <- upload_file_2.(filepath, firmware.upload_metadata) do
          {:ok, firmware}
        end
      end,
      timeout: 60_000
    )
    |> case do
      {:ok, firmware} ->
        _ = Products.PubSub.broadcast_from(firmware.product_id, "firmware/created", %{firmware: firmware})

        {:ok, firmware}

      {:error, error} ->
        Logger.error(fn -> "Error while publishing firmware: #{inspect(error)}" end)
        {:error, error}
    end
  end

  @spec delete_firmware(Firmware.t()) ::
          {:ok, Firmware.t()} | {:error, Ecto.Changeset.t()} | none()
  def delete_firmware(%Firmware{} = firmware) do
    changeset = Firmware.delete_changeset(firmware)
    delete_firmware_job = DeleteFirmware.new(firmware.upload_metadata)

    Repo.transact(fn ->
      with {:ok, firmware} <- Repo.delete(changeset),
           {:ok, _} <- Oban.insert(delete_firmware_job) do
        {:ok, firmware}
      end
    end)
    |> case do
      {:ok, firmware} ->
        _ = Products.PubSub.broadcast_from(firmware.product_id, "firmware/deleted", %{firmware: firmware})

        {:ok, firmware}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec delete_firmware_delta(FirmwareDelta.t()) ::
          {:ok, FirmwareDelta.t()} | {:error, Ecto.Changeset.t() | Oban.Job.changeset()}
  def delete_firmware_delta(%FirmwareDelta{} = delta) do
    delete_delta_job = DeleteFirmware.new(delta.upload_metadata)

    Repo.transact(fn ->
      with {:ok, firmware} <- Repo.delete(delta),
           {:ok, _} = ManagedDeployments.recalculate_deployment_group_status_by_firmware_id(delta.target_id),
           {:ok, _} <- Oban.insert(delete_delta_job) do
        {:ok, firmware}
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

  @spec metadata_from_device(metadata :: map(), product_id :: pos_integer()) ::
          {:ok, FirmwareMetadata.t() | nil}
  def metadata_from_device(metadata, product_id) do
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
            case get_firmware_by_product_id_and_uuid(product_id, uuid) do
              {:error, _} ->
                {:ok, nil}

              {:ok, firmware} ->
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

  @spec get_firmware_delta_by_source_and_target(non_neg_integer(), non_neg_integer(), :all | nil | [atom()]) ::
          {:ok, FirmwareDelta.t()}
          | {:error, :not_found}
  def get_firmware_delta_by_source_and_target(source_id, target_id, status \\ :all) do
    FirmwareDelta
    |> where([fd], source_id: ^source_id)
    |> where([fd], target_id: ^target_id)
    |> then(fn query ->
      if is_nil(status) or status == :all do
        query
      else
        where(query, [fd], fd.status in ^status)
      end
    end)
    |> Repo.fetch()
  end

  @spec get_firmware_url(Firmware.t() | FirmwareDelta.t()) ::
          {:ok, String.t()}
          | {:error, :failure}
  def get_firmware_url(fw_or_delta) do
    firmware_upload_config().download_file(fw_or_delta)
  end

  @doc """
  Returns true if the device is delta updatable.

  Checks update tool version information and similar metadata to determine if
  the device is delta updatable.
  """
  @spec delta_updatable?(Device.t(), DeploymentGroup.t() | Firmware.t()) :: boolean()
  def delta_updatable?(device, %DeploymentGroup{} = deployment_group) do
    Logger.metadata(device_id: device.id, deployment_group_id: deployment_group.id)
    # note that source delta does not need delta markers to be updatable
    # Any advanced decision about whether to delta update or not are delegated
    # to the specialized update tool implementation

    deployment_group.delta_updatable and
      not is_nil(deployment_group.current_release.firmware) and
      delta_updatable?(device, deployment_group.current_release.firmware)
  end

  def delta_updatable?(%{firmware_metadata: fw_meta} = device, %Firmware{} = firmware) do
    Logger.metadata(
      device_id: device.id,
      target_firmware_uuid: firmware.uuid,
      source_firmware_uuid: Map.get(fw_meta, :uuid)
    )

    firmware.delta_updatable and
      :delta == update_tool().device_update_type(device, firmware)
  end

  @spec delta_ready?(Device.t(), Firmware.t()) :: boolean()
  def delta_ready?(%Device{firmware_metadata: %{uuid: source_uuid}}, %Firmware{id: target_id, product_id: product_id}) do
    source_uuid
    |> firmware_delta_query(product_id, target_id)
    |> where([fd], fd.status == :completed)
    |> Repo.exists?()
  end

  @spec get_delta_or_firmware(Device.t(), DeploymentGroup.t()) ::
          {:ok, Firmware.t()} | {:ok, FirmwareDelta.t()}
  def get_delta_or_firmware(%Device{firmware_metadata: %{uuid: source_uuid}} = device, %DeploymentGroup{
        delta_updatable: true,
        current_release: %DeploymentRelease{firmware: %Firmware{delta_updatable: true} = target_firmware}
      }) do
    case get_firmware_by_product_id_and_uuid(device.product_id, source_uuid) do
      {:ok, source_firmware} ->
        case get_delta_if_ready(device, source_firmware, target_firmware) do
          {:ok, delta} ->
            {:ok, delta}

          _ ->
            {:ok, target_firmware}
        end

      {:error, :not_found} ->
        {:ok, target_firmware}
    end
  end

  def get_delta_or_firmware(%Device{}, %DeploymentGroup{current_release: %{firmware: target}}), do: {:ok, target}

  @spec get_delta_url(Device.t(), Firmware.t()) ::
          {:ok, String.t()}
          | {:error, :failure}
  def get_delta_url(%Device{firmware_metadata: %{uuid: source_uuid}}, %Firmware{id: target_id, product_id: product_id}) do
    source_uuid
    |> firmware_delta_query(product_id, target_id)
    |> Repo.one()
    |> get_firmware_url()
  end

  @spec get_delta_if_ready(Device.t(), Firmware.t(), Firmware.t()) ::
          {:ok, FirmwareDelta.t()}
          | {:device_delta_updatable, false}
          | {:delta, {:ok, FirmwareDelta.t()}}
          | {:delta, {:error, :not_found}}
  defp get_delta_if_ready(device, source_firmware, target_firmware) do
    with {:device_delta_updatable, true} <-
           {:device_delta_updatable, delta_updatable?(device, target_firmware)},
         {:delta, {:ok, %{status: :completed} = delta}} <-
           {:delta,
            get_firmware_delta_by_source_and_target(
              source_firmware.id,
              target_firmware.id
            )} do
      {:ok, delta}
    end
  end

  # Builds the FirmwareDelta query from the device's current (source) firmware
  # UUID to the target firmware id. Shared by delta_ready?/2 and get_delta_url/2.
  defp firmware_delta_query(source_uuid, product_id, target_id) do
    source_firmware_id_query =
      Firmware
      |> where(uuid: ^source_uuid)
      |> where(product_id: ^product_id)
      |> select([f], f.id)

    FirmwareDelta
    |> where([fd], fd.source_id == subquery(source_firmware_id_query))
    |> where([fd], fd.target_id == ^target_id)
  end

  @spec generate_firmware_delta(FirmwareDelta.t(), Firmware.t(), Firmware.t()) ::
          :ok
          | {:error, Ecto.Changeset.t() | :no_delta_support_in_firmware}
  def generate_firmware_delta(firmware_delta, source_firmware, target_firmware) do
    {:ok, work_dir} = Briefly.create(type: :directory)

    Logger.info("Creating firmware delta between #{source_firmware.uuid} and #{target_firmware.uuid}.")

    {:ok, source_url} = firmware_upload_config().download_file(source_firmware)
    {:ok, target_url} = firmware_upload_config().download_file(target_firmware)

    case update_tool().create_firmware_delta_file(
           {source_firmware.uuid, source_url},
           {target_firmware.uuid, target_url},
           work_dir
         ) do
      {:ok, delta_file_metadata} ->
        case finalize_delta(firmware_delta, source_firmware, target_firmware, delta_file_metadata) do
          {:ok, _delta} ->
            :ok

          {:error, err} ->
            _ = fail_firmware_delta(firmware_delta)
            {:error, err}
        end

      {:error, _} = error ->
        error
    end
  after
    Briefly.cleanup()
  end

  defp finalize_delta(firmware_delta, source_firmware, target_firmware, delta_file_metadata) do
    upload_metadata =
      firmware_upload_config().delta_metadata(
        source_firmware.org_id,
        source_firmware.uuid,
        target_firmware.uuid
      )

    checksum = firmware_checksum(delta_file_metadata.filepath)
    partials_checksums = partials_checksums(delta_file_metadata.filepath)

    changeset =
      FirmwareDelta.complete_changeset(
        firmware_delta,
        delta_file_metadata.tool,
        delta_file_metadata.size,
        delta_file_metadata.source_size,
        delta_file_metadata.target_size,
        delta_file_metadata.tool_metadata,
        upload_metadata,
        checksum,
        partials_checksums
      )

    with {:ok, firmware_delta} <- Repo.update(changeset),
         :ok <- firmware_upload_config().upload_file(delta_file_metadata.filepath, upload_metadata),
         {:ok, _firmware_delta} <- notify_firmware_delta_target({:ok, firmware_delta}) do
      {:ok, _} = ManagedDeployments.recalculate_deployment_group_status_by_firmware_id(firmware_delta.target_id)

      Logger.info("Created firmware delta successfully.")

      :ok = update_tool().cleanup_firmware_delta_files(delta_file_metadata.filepath)

      {:ok, firmware_delta}
    else
      {:error, error} ->
        Logger.error("Failed when finalizing firmware delta: #{inspect(error)}")

        :ok = update_tool().cleanup_firmware_delta_files(delta_file_metadata.filepath)

        {:error, error}
    end
  end

  defp with_product(query) do
    query
    |> join(:left, [f], p in assoc(f, :product))
    |> preload([d, p], product: p)
  end

  @spec attempt_firmware_delta(
          source_id :: non_neg_integer(),
          target_id :: non_neg_integer(),
          recalculate_deployment_statuses :: boolean()
        ) ::
          {:ok, :started}
          | {:error, :delta_already_exists}
          | {:error, :failed_to_insert_delta}
          | {:error, :failed_to_insert_job}
  def attempt_firmware_delta(source_id, target_id, recalculate_deployment_statuses \\ true) do
    Repo.transact(fn ->
      with {:error, :not_found} <-
             get_firmware_delta_by_source_and_target(source_id, target_id, [:processing, :completed]),
           {_, {:ok, _}} <-
             {:delta_insert, start_firmware_delta(source_id, target_id, recalculate_deployment_statuses)},
           {_, {:ok, _}} <-
             {:job, Oban.insert(FirmwareDeltaBuilder.new(%{source_id: source_id, target_id: target_id}))} do
        {:ok, :started}
      else
        {:ok, %FirmwareDelta{}} ->
          {:ok, :delta_already_exists}

        {:delta_insert,
         {:error,
          [
            {:unique_firmware_delta,
             {"has already been taken", [constraint: :unique, constraint_name: "source_id_target_id_unique_index"]}}
          ]}} ->
          # a race condition exists where multiple devices connect, are added to a deployment group, and
          # try to create a delta, only for one to 'start' but all others fail.
          # This should be regarded as an `:ok` response.
          {:ok, :delta_already_exists}

        {:delta_insert, {:error, changeset}} ->
          Logger.warning("Failed to insert firmware delta for #{source_id} -> #{target_id}")

          Logging.log_message_to_sentry("Failed to insert firmware delta", %{
            errors: changeset.errors
          })

          {:error, :failed_to_insert_delta}

        {:job, {:error, changeset}} ->
          Logger.warning("Failed to insert firmware delta job for #{source_id} -> #{target_id}")

          Logging.log_message_to_sentry("Failed to insert firmware delta job", %{
            errors: changeset.errors
          })

          {:error, :failed_to_insert_job}
      end
    end)
  end

  @spec start_firmware_delta(non_neg_integer(), non_neg_integer()) ::
          {:ok, FirmwareDelta.t()} | {:error, Ecto.Changeset.t()}
  def start_firmware_delta(source_id, target_id, recalculate_deployment_statuses \\ true) do
    _ =
      get_firmware_delta_by_source_and_target(source_id, target_id, [:failed, :timed_out])
      |> case do
        {:ok, firmware_delta} -> {:ok, _} = Repo.delete(firmware_delta)
        {:error, _} -> :ok
      end

    %FirmwareDelta{}
    |> FirmwareDelta.start_changeset(source_id, target_id)
    |> Repo.insert()
    |> notify_firmware_delta_target()
    |> case do
      {:ok, firmware_delta} ->
        _ =
          if recalculate_deployment_statuses do
            {:ok, _} = ManagedDeployments.recalculate_deployment_group_status_by_firmware_id(target_id)
          end

        {:ok, firmware_delta}

      passthrough ->
        passthrough
    end
  end

  @spec fail_firmware_delta(FirmwareDelta.t()) ::
          {:ok, FirmwareDelta.t()} | {:error, Ecto.Changeset.t()}
  def fail_firmware_delta(%FirmwareDelta{} = firmware_delta) do
    {:ok, firmware_delta} =
      firmware_delta
      |> FirmwareDelta.fail_changeset()
      |> Repo.update()
      |> notify_firmware_delta_target()

    {:ok, _} = ManagedDeployments.recalculate_deployment_group_status_by_firmware_id(firmware_delta.target_id)

    {:ok, firmware_delta}
  end

  @spec time_out_firmware_delta(FirmwareDelta.t()) ::
          {:ok, FirmwareDelta.t()} | {:error, Ecto.Changeset.t()}
  def time_out_firmware_delta(%FirmwareDelta{} = firmware_delta) do
    {:ok, firmware_delta} =
      firmware_delta
      |> FirmwareDelta.time_out_changeset()
      |> Repo.update()
      |> notify_firmware_delta_target()

    {:ok, _} =
      ManagedDeployments.recalculate_deployment_group_status_by_firmware_id(firmware_delta.target_id)

    {:ok, firmware_delta}
  end

  @spec subscribe_firmware_delta_target(target_id :: integer()) :: :ok
  def subscribe_firmware_delta_target(target_id) do
    Group.join(NervesHub.Group, firmware_delta_topic(target_id), %{})
  end

  @doc """
  Leave a firmware's delta group.

  Callers that follow a moving target (the deployment group summary follows the
  current release's firmware) must leave the previous target, otherwise
  memberships accumulate for the lifetime of the process — and unlike a local
  `Phoenix.PubSub` subscription, `:group` membership is replicated to every node.

  Leaving a group the caller never joined is not an error.
  """
  @spec unsubscribe_firmware_delta_target(target_id :: integer()) :: :ok
  def unsubscribe_firmware_delta_target(target_id) do
    case Group.leave(NervesHub.Group, firmware_delta_topic(target_id)) do
      :ok -> :ok
      {:error, :not_in_group} -> :ok
    end
  end

  defp notify_firmware_delta_target({:ok, %FirmwareDelta{} = firmware_delta}) do
    message = %Broadcast{
      topic: firmware_delta_topic(firmware_delta.target_id),
      event: "delta/status_update",
      payload: %{
        delta_id: firmware_delta.id,
        source_firmware_id: firmware_delta.source_id,
        status: firmware_delta.status
      }
    }

    :ok = Group.dispatch(NervesHub.Group, firmware_delta_topic(firmware_delta.target_id), message)

    {:ok, firmware_delta}
  end

  defp notify_firmware_delta_target(error), do: error

  # Preserved as the previous `Phoenix.PubSub` topic string; receivers match on
  # the `"firmware:" <> _` prefix.
  defp firmware_delta_topic(target_id), do: "firmware:#{target_id}"

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

  @spec time_out_firmware_delta_generations(
          age :: non_neg_integer(),
          unit :: :second | :millisecond | :minute
        ) ::
          :ok
  def time_out_firmware_delta_generations(age_seconds, unit) do
    cutoff = DateTime.add(DateTime.utc_now(), -age_seconds, unit)

    FirmwareDelta
    |> where([fd], fd.status == :processing)
    |> where([fd], fd.inserted_at < ^cutoff)
    |> Repo.all()
    |> Enum.each(fn firmware_delta ->
      {:ok, _firmware_delta} = time_out_firmware_delta(firmware_delta)
    end)

    :ok
  end

  @spec build_firmware_params(Org.t(), Path.t()) :: {:ok, map()} | {:error, any()}
  defp build_firmware_params(%{id: org_id} = org, filepath) do
    org = NervesHub.Repo.preload(org, :org_keys)

    with {:ok, %{id: org_key_id}} <- verify_signature(filepath, org.org_keys),
         {:ok, %{path: conf_path, firmware_metadata: fm, tool_metadata: tm} = m} <-
           update_tool().get_firmware_metadata_from_file(filepath) do
      filename = fm.uuid <> ".fw"

      params =
        %{
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
        }
        |> calculate_checksums()
        |> resolve_product()

      {:ok, params}
    end
  end

  defp calculate_checksums(params) do
    params
    |> Map.put(:checksum, firmware_checksum(params.filepath))
    |> Map.put(:partials_checksums, partials_checksums(params.filepath))
  end

  def firmware_checksum(filepath) do
    filepath
    |> File.stream!(2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn bytes, hash_state ->
      :crypto.hash_update(hash_state, bytes)
    end)
    |> :crypto.hash_final()
    |> Base.encode16()
  end

  def partials_checksums(filepath) do
    filepath
    |> File.stream!(@firmware_partial_chunk_size)
    |> Stream.map(fn chunk ->
      :crypto.hash(:sha256, chunk) |> Base.encode16()
    end)
    |> Enum.to_list()
  end

  defp resolve_product(params) do
    case Products.get_product_by_org_id_and_name(params.org_id, params.product_name) do
      {:ok, product} ->
        params
        |> Map.put(:product_id, product.id)
        |> Map.put(:require_unique_firmware_version, product.require_unique_firmware_version)

      _ ->
        params
    end
  end

  defp update_tool() do
    Application.get_env(
      :nerves_hub,
      :update_tool,
      # Fall back to old config key
      Application.get_env(:nerves_hub, :delta_updater, Fwup)
    )
  end
end
