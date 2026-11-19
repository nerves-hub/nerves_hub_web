defmodule NervesHub.Firmwares do
  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceFirmware
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Firmwares.FirmwareTransfer
  alias NervesHub.Firmwares.PubSub
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Firmwares.UpdateTool.Fwup
  alias NervesHub.Helpers.Logging
  alias NervesHub.ListQuery
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Workers.DeleteFirmware
  alias NervesHub.Workers.FirmwareDeltaBuilder

  require Logger

  @firmware_partial_chunk_size 1024 * 1024

  @type upload_file_2 :: (filepath :: String.t(), filename :: String.t() -> :ok | {:error, any()})

  # Firmware is soft deleted (see `delete_firmware/2`), so every getter here
  # excludes deleted firmware unless it is explicitly asked not to. Defaulting
  # the other way puts the burden on each call site to remember that the file
  # behind the row is gone, and a call site added later would inherit the wrong
  # answer silently.
  #
  # `include_deleted: true` is for the handful of callers that want history
  # rather than something to act on: the firmware show page, which renders a
  # deleted state; `DeviceFirmware.create_changeset/4`, which resolves a
  # reporting device's firmware by uuid and should keep pointing at the right row
  # rather than recording a bare `nil`; and the update statistics, which are
  # about firmware that has already shipped.

  defp firmware_upload_config(), do: Application.fetch_env!(:nerves_hub, :firmware_upload)

  @spec get_by_id(Product.t() | DeploymentGroup.t(), pos_integer()) :: Firmware.t() | nil
  def get_by_id(_product, firmware_id) when firmware_id in [nil, ""], do: nil

  def get_by_id(%DeploymentGroup{} = deployment_group, firmware_id) do
    Firmware
    |> where([f], f.platform == ^deployment_group.platform)
    |> where([f], f.architecture == ^deployment_group.architecture)
    |> where([f], f.product_id == ^deployment_group.product_id)
    |> where([f], f.id == ^firmware_id)
    |> Repo.exclude_deleted()
    |> Repo.one()
  end

  def get_by_id(%Product{} = product, firmware_id) do
    Firmware
    |> where([f], f.product_id == ^product.id)
    |> where([f], f.id == ^firmware_id)
    |> Repo.exclude_deleted()
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
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  @spec get_unique_platforms(Product.t()) :: [String.t()]
  def get_unique_platforms(product) do
    Firmware
    |> select([f], f.platform)
    |> distinct(true)
    |> where([f], f.product_id == ^product.id)
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  @spec get_unique_tools(Product.t()) :: [String.t()]
  def get_unique_tools(product) do
    Firmware
    |> select([f], f.tool)
    |> distinct(true)
    |> where([f], f.product_id == ^product.id)
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  @spec get_unique_architectures(Product.t()) :: [String.t()]
  def get_unique_architectures(product) do
    Firmware
    |> select([f], f.architecture)
    |> distinct(true)
    |> where([f], f.product_id == ^product.id)
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  @spec get_firmwares_by_product(integer()) :: [Firmware.t()]
  def get_firmwares_by_product(product_id) do
    Firmware
    |> where([f], f.product_id == ^product_id)
    |> Repo.exclude_deleted()
    |> order_by_latest_version()
    |> with_product()
    |> Repo.all()
  end

  @spec get_firmwares_by_product_and_platform(Product.t(), String.t()) :: [Firmware.t()]
  def get_firmwares_by_product_and_platform(product, platform) do
    Firmware
    |> where([f], f.product_id == ^product.id)
    |> where([f], f.platform == ^platform)
    |> Repo.exclude_deleted()
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
    |> Repo.exclude_deleted()
    |> order_by_latest_version()
    |> limit(25)
    |> Repo.all()
  end

  @typedoc """
  Which of a product's firmware the firmware list shows.

  `:in_use` is firmware a device is running or a deployment group's current
  release names; `:not_in_use` is the rest. Neither includes deleted firmware,
  which only `:deleted` shows.
  """
  @type list_tab() :: :all | :in_use | :not_in_use | :deleted

  @type list_opts() :: %{
          optional(:tab) => list_tab(),
          optional(:search) => String.t() | nil,
          optional(:platform) => String.t() | nil,
          optional(:tool) => String.t() | nil,
          optional(:sort) => String.t(),
          optional(:sort_direction) => String.t(),
          optional(:page) => String.t() | pos_integer(),
          optional(:page_size) => String.t() | pos_integer()
        }

  @list_sorts ~w(inserted_at version install_count)

  @doc """
  A page of the product's firmware, for the firmware list.

  Each firmware carries `install_count`, the number of the product's devices
  running it now. `opts` picks the tab (see `t:list_tab/0`), narrows by
  `search` (the start of a version, UUID or VCS identifier), `platform` and
  `tool`, and sorts by `inserted_at` (the default), `version` or
  `install_count`. A page holds 25 firmware unless `page_size` says
  otherwise, and never more than 100.
  """
  @spec list_firmware(Product.t(), list_opts()) :: {[Firmware.t()], Flop.Meta.t()}
  def list_firmware(%Product{} = product, opts \\ %{}) do
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) or val == "" end)

    sort = if opts[:sort] in @list_sorts, do: opts[:sort], else: "inserted_at"
    sort_direction = if opts[:sort_direction] == "asc", do: :asc, else: :desc

    flop = %Flop{
      page: ListQuery.positive_integer(opts[:page], 1),
      # The pager offers 25, 50 and 100. Anything bigger only comes from an
      # edited URL, so it is held to the largest of those.
      page_size: min(ListQuery.positive_integer(opts[:page_size], 25), 100)
    }

    product
    |> firmware_with_install_counts()
    |> where_tab(Map.get(opts, :tab, :all))
    |> where_search(opts[:search])
    |> where_field(:platform, opts[:platform])
    |> where_field(:tool, opts[:tool])
    |> preload(:deleted_by)
    |> sort_firmware({sort_direction, String.to_existing_atom(sort)})
    |> select_merge([installs: i], %{install_count: coalesce(i.install_count, 0)})
    |> Flop.run(flop)
  end

  @doc """
  How many of the product's firmware each tab of the firmware list holds, and
  how many distinct versions the firmware that isn't deleted spans.
  """
  @spec list_counts(Product.t()) :: %{
          all: non_neg_integer(),
          in_use: non_neg_integer(),
          not_in_use: non_neg_integer(),
          deleted: non_neg_integer(),
          versions: non_neg_integer()
        }
  def list_counts(%Product{} = product) do
    counts =
      product
      |> firmware_with_install_counts()
      |> select([firmware: f, installs: i], %{
        all: filter(count(f.id), is_nil(f.deleted_at)),
        in_use:
          filter(
            count(f.id),
            is_nil(f.deleted_at) and
              (coalesce(i.install_count, 0) > 0 or exists(current_release_of_query()))
          ),
        deleted: filter(count(f.id), not is_nil(f.deleted_at)),
        versions: filter(count(f.version, :distinct), is_nil(f.deleted_at))
      })
      |> Repo.one()

    Map.put(counts, :not_in_use, counts.all - counts.in_use)
  end

  @doc """
  Which deployment groups use each of the given firmware, as their current
  release or the one before it, keyed by firmware id.

  A group whose previous release is the same firmware as its current one is
  only listed as current.
  """
  @spec used_by(Product.t(), [pos_integer()]) :: %{
          pos_integer() => [%{deployment_group: DeploymentGroup.t(), release: :current | :previous}]
        }
  def used_by(_product, []), do: %{}

  def used_by(%Product{} = product, firmware_ids) do
    current =
      DeploymentGroup
      |> join(:inner, [dg], cr in assoc(dg, :current_release))
      |> where([dg], dg.product_id == ^product.id)
      |> where([_dg, cr], cr.firmware_id in ^firmware_ids)
      |> select([dg, cr], {cr.firmware_id, dg, :current})

    previous =
      DeploymentGroup
      |> join(:inner, [dg], cr in assoc(dg, :current_release))
      |> join(:inner, [dg, cr], pr in DeploymentRelease,
        on: pr.deployment_group_id == dg.id and pr.number == cr.number - 1
      )
      |> where([dg], dg.product_id == ^product.id)
      |> where([_dg, cr, pr], pr.firmware_id in ^firmware_ids and pr.firmware_id != cr.firmware_id)
      |> select([dg, _cr, pr], {pr.firmware_id, dg, :previous})

    (Repo.all(current) ++ Repo.all(previous))
    |> Enum.sort_by(fn {_firmware_id, group, release} -> {release != :current, group.name} end)
    |> Enum.group_by(
      fn {firmware_id, _group, _release} -> firmware_id end,
      fn {_firmware_id, group, release} -> %{deployment_group: group, release: release} end
    )
  end

  @doc """
  Where a firmware stands across its product, for the firmware's page.

    * `:running` - the product's devices running it now.
    * `:product_devices` - all of the product's devices, to put `:running` in
      proportion.
    * `:updating` - devices being moved to it right now.
    * `:installed` - devices that have ever installed it, counting each once.
  """
  @spec usage(Firmware.t()) :: %{
          running: non_neg_integer(),
          product_devices: non_neg_integer(),
          updating: non_neg_integer(),
          installed: non_neg_integer()
        }
  def usage(%Firmware{} = firmware) do
    devices =
      Device
      |> where([d], d.product_id == ^firmware.product_id)
      |> Repo.exclude_deleted()
      |> select([d], %{
        product_devices: count(d.id),
        running: filter(count(d.id), fragment("? ->> 'uuid'", d.firmware_metadata) == ^firmware.uuid)
      })
      |> Repo.one()

    updating =
      InflightUpdate
      |> where([iu], iu.firmware_id == ^firmware.id)
      |> Repo.aggregate(:count)

    installed =
      DeviceFirmware
      |> where([df], df.firmware_id == ^firmware.id)
      |> select([df], count(df.device_id, :distinct))
      |> Repo.one()

    Map.merge(devices, %{updating: updating, installed: installed})
  end

  @doc """
  How far each of the given deployment groups has got with a firmware, keyed
  by group id: the devices in the group, how many run the firmware now, and
  how many are being moved to it.
  """
  @spec release_progress(Firmware.t(), [pos_integer()]) :: %{
          pos_integer() => %{devices: non_neg_integer(), running: non_neg_integer(), updating: non_neg_integer()}
        }
  def release_progress(_firmware, []), do: %{}

  def release_progress(%Firmware{} = firmware, group_ids) do
    updating =
      InflightUpdate
      |> where([iu], iu.firmware_id == ^firmware.id and iu.deployment_id in ^group_ids)
      |> group_by([iu], iu.deployment_id)
      |> select([iu], {iu.deployment_id, count(iu.id)})
      |> Repo.all()
      |> Map.new()

    devices =
      Device
      |> where([d], d.deployment_id in ^group_ids)
      |> Repo.exclude_deleted()
      |> group_by([d], d.deployment_id)
      |> select(
        [d],
        {d.deployment_id, count(d.id),
         filter(count(d.id), fragment("? ->> 'uuid'", d.firmware_metadata) == ^firmware.uuid)}
      )
      |> Repo.all()
      |> Map.new(fn {group_id, total, running} -> {group_id, {total, running}} end)

    Map.new(group_ids, fn group_id ->
      {total, running} = Map.get(devices, group_id, {0, 0})
      {group_id, %{devices: total, running: running, updating: Map.get(updating, group_id, 0)}}
    end)
  end

  @doc """
  The product's other firmware with the same version as this one, ordered by
  platform then architecture.

  Each carries `install_count`, the devices running it now. Deleted firmware is
  left out.
  """
  @spec other_builds(Firmware.t()) :: [Firmware.t()]
  def other_builds(%Firmware{} = firmware) do
    %Product{id: firmware.product_id}
    |> firmware_with_install_counts()
    |> Repo.exclude_deleted()
    |> where([firmware: f], f.version == ^firmware.version and f.id != ^firmware.id)
    |> order_by([firmware: f], asc: f.platform, asc: f.architecture)
    |> select_merge([installs: i], %{install_count: coalesce(i.install_count, 0)})
    |> Repo.all()
  end

  # Every firmware of the product, deleted or not, joined to how many of the
  # product's devices run it now.
  defp firmware_with_install_counts(product) do
    installs =
      Device
      |> where([d], d.product_id == ^product.id)
      |> where([d], not is_nil(fragment("? ->> 'uuid'", d.firmware_metadata)))
      |> Repo.exclude_deleted()
      |> group_by([d], fragment("? ->> 'uuid'", d.firmware_metadata))
      |> select([d], %{
        firmware_uuid: fragment("? ->> 'uuid'", d.firmware_metadata),
        install_count: count(d.id)
      })

    Firmware
    |> from(as: :firmware)
    |> join(:left, [firmware: f], i in subquery(installs), on: i.firmware_uuid == f.uuid, as: :installs)
    |> where([firmware: f], f.product_id == ^product.id)
  end

  defp current_release_of_query() do
    DeploymentGroup
    |> join(:inner, [dg], cr in assoc(dg, :current_release))
    |> where([_dg, cr], cr.firmware_id == parent_as(:firmware).id)
    |> select(1)
  end

  defp where_tab(query, :deleted), do: where(query, [firmware: f], not is_nil(f.deleted_at))
  defp where_tab(query, :all), do: Repo.exclude_deleted(query)

  defp where_tab(query, :in_use) do
    query
    |> Repo.exclude_deleted()
    |> where([installs: i], coalesce(i.install_count, 0) > 0 or exists(current_release_of_query()))
  end

  defp where_tab(query, :not_in_use) do
    query
    |> Repo.exclude_deleted()
    |> where([installs: i], coalesce(i.install_count, 0) == 0 and not exists(current_release_of_query()))
  end

  defp where_search(query, nil), do: query

  defp where_search(query, search) do
    prefix = ListQuery.escape_like(String.trim(search)) <> "%"

    where(
      query,
      [firmware: f],
      ilike(f.version, ^prefix) or ilike(f.uuid, ^prefix) or ilike(f.vcs_identifier, ^prefix)
    )
  end

  defp where_field(query, _field, nil), do: query
  defp where_field(query, field, value), do: where(query, [firmware: f], field(f, ^field) == ^value)

  defp sort_firmware(query, {direction, :install_count}) do
    order_by(query, [installs: i], [{^direction, coalesce(i.install_count, 0)}, desc: :inserted_at])
  end

  defp sort_firmware(query, {direction, :version}) do
    order_by(query, [f], [
      {^version_sort_direction(direction), fragment(~s|semver_sort_key(?) COLLATE "C"|, f.version)}
    ])
  end

  defp sort_firmware(query, sort), do: order_by(query, ^[sort, desc: :id])

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
    |> Repo.exclude_deleted()
    |> order_by_latest_version()
    |> with_product()
    |> Repo.all()
  end

  @doc """
  The product's firmwares as `%{version, uuid}` maps, newest version first.
  """
  def firmware_versions_and_uuids(product_id) do
    Firmware
    |> where([f], f.product_id == ^product_id)
    |> Repo.exclude_deleted()
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
    |> Repo.exclude_deleted()
    |> Repo.fetch()
  end

  def get_firmware(%Product{id: product_id}, id) do
    Firmware
    |> where([f], f.id == ^id)
    |> where([f], f.product_id == ^product_id)
    |> Repo.exclude_deleted()
    |> Repo.fetch()
  end

  def get_firmware!(firmware_id), do: Repo.get!(Firmware, firmware_id)

  @doc """
  Preloads a firmware's product.
  """
  def preload_product(%Firmware{} = firmware), do: Repo.preload(firmware, :product)

  @doc """
  Preloads the user who deleted this firmware, if anyone has.
  """
  def preload_deleted_by(%Firmware{} = firmware), do: Repo.preload(firmware, :deleted_by)

  def get_firmware_for_device(%Device{firmware_metadata: nil}), do: []

  def get_firmware_for_device(device) do
    Firmware
    |> where([f], f.platform == ^device.firmware_metadata.platform)
    |> where([f], f.architecture == ^device.firmware_metadata.architecture)
    |> where([f], f.org_id == ^device.org_id)
    |> where([f], f.product_id == ^device.product_id)
    |> Repo.exclude_deleted()
    |> order_by_latest_version()
    |> Repo.all()
  end

  @spec get_firmware_by_org_id(non_neg_integer()) :: [Firmware.t()]
  def get_firmware_by_org_id(org_id) do
    Firmware
    |> with_product()
    |> where([f, p], p.org_id == ^org_id)
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  @spec get_firmware_by_product_id_and_uuid(integer(), String.t() | nil, keyword()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware_by_product_id_and_uuid(product_id, uuid, opts \\ [])

  def get_firmware_by_product_id_and_uuid(_product_id, nil, _opts) do
    {:error, :not_found}
  end

  def get_firmware_by_product_id_and_uuid(product_id, uuid, opts) do
    get_firmware_by_product_and_uuid_query(%Product{id: product_id}, uuid, opts)
    |> Repo.fetch()
  end

  @spec get_firmware_by_uuid(Scope.t(), String.t(), keyword()) :: {:ok, Firmware.t()} | {:error, :not_found}
  def get_firmware_by_uuid(%Scope{} = scope, uuid, opts \\ []) do
    get_firmware_by_product_and_uuid(scope.product, uuid, opts)
  end

  @spec get_firmware_by_uuid!(Scope.t(), String.t(), keyword()) :: Firmware.t()
  def get_firmware_by_uuid!(%Scope{} = scope, uuid, opts \\ []) do
    get_firmware_by_product_and_uuid_query(scope.product, uuid, opts)
    |> Repo.one!()
  end

  @spec get_firmware_by_product_and_uuid(Product.t(), String.t(), keyword()) ::
          {:ok, Firmware.t()}
          | {:error, :not_found}
  def get_firmware_by_product_and_uuid(%Product{} = product, uuid, opts \\ []) do
    get_firmware_by_product_and_uuid_query(product, uuid, opts)
    |> Repo.fetch()
  end

  defp get_firmware_by_product_and_uuid_query(%Product{id: product_id}, uuid, opts \\ []) do
    query =
      Firmware
      |> with_product()
      |> where([f], f.uuid == ^uuid)
      |> where([f, p], p.id == ^product_id)

    if opts[:include_deleted] do
      # `firmwares_product_id_uuid_index` covers live firmware only, so the same
      # uuid can name both a live row and the deleted row whose place it took —
      # deleting a build and uploading it again is the whole point of the index
      # being partial. Prefer the live one, and fall back to the deleted row when
      # that is all there is, so a uuid still resolves to exactly one firmware.
      query
      |> order_by([f], asc_nulls_first: f.deleted_at)
      |> limit(1)
    else
      Repo.exclude_deleted(query)
    end
  end

  @doc """
  Store an uploaded firmware file.

  Pass `:product` to require that the archive's own declared product name
  matches the product the upload was addressed to. Without it the declared name
  alone decides where the firmware lands, which is how this behaved before the
  option existed.
  """
  @spec create_firmware(
          org :: Org.t(),
          filepath :: Path.t(),
          opts :: [{:upload_file_2, upload_file_2()} | {:product, Product.t()}]
        ) ::
          {:ok, Firmware.t()}
          | {:error,
             Changeset.t()
             | :no_public_keys
             | :invalid_signature
             | {:fwup_too_old, required :: String.t(), installed :: String.t()}
             | {:product_mismatch, declared :: String.t(), expected :: String.t()}
             | any}
  def create_firmware(org, filepath, opts \\ []) do
    upload_file_2 = opts[:upload_file_2] || (&firmware_upload_config().upload_file(&1, &2))

    Repo.transact(
      fn ->
        with {:ok, params} <- build_firmware_params(org, filepath, opts[:product]),
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

  @typedoc """
  A reason firmware cannot be deleted.

  `:current_release` carries the deployment groups pinning it, so the caller can
  name them. `:inflight_updates` carries how many devices are mid-update.
  """
  @type deletion_blocker ::
          :already_deleted
          | {:current_release, [DeploymentGroup.t()]}
          | {:inflight_updates, pos_integer()}

  @typedoc """
  Something a user should know before deleting firmware, but which does not stop
  them. `:delta_source` carries how many deltas are built from this firmware.
  """
  @type deletion_warning :: {:delta_source, pos_integer()}

  @doc """
  Why this firmware cannot be deleted, or `[]` if it can.

  Deleting firmware removes the file behind it, so the two things that block it
  are the two that would leave a device reaching for a file that is gone: being
  the current release of a deployment group, and having updates in flight.

  Being a delta *source* is deliberately not a blocker — losing delta generation
  costs bandwidth, it does not break an update. See `deletion_warnings/1`.
  """
  @spec deletion_blockers(Firmware.t()) :: [deletion_blocker()]
  def deletion_blockers(%Firmware{} = firmware) do
    if Firmware.deleted?(firmware) do
      [:already_deleted]
    else
      current_release_blockers(firmware) ++ inflight_update_blockers(firmware)
    end
  end

  @doc """
  Whether this firmware can be deleted right now.
  """
  @spec deletable?(Firmware.t()) :: boolean()
  def deletable?(%Firmware{} = firmware), do: deletion_blockers(firmware) == []

  defp current_release_blockers(firmware) do
    DeploymentGroup
    |> from(as: :deployment_group)
    |> join(:inner, [deployment_group: dg], dr in assoc(dg, :current_release), as: :current_release)
    |> where([current_release: cr], cr.firmware_id == ^firmware.id)
    |> Repo.all()
    |> case do
      [] -> []
      deployment_groups -> [{:current_release, deployment_groups}]
    end
  end

  # Every `inflight_updates` row is an active one — reaching an outcome deletes
  # it, see `NervesHub.Devices.InflightUpdate` — but say so in the query rather
  # than depending on it.
  defp inflight_update_blockers(firmware) do
    InflightUpdate
    |> where([iu], iu.firmware_id == ^firmware.id)
    |> where([iu], iu.status in ^InflightUpdate.active_statuses())
    |> Repo.aggregate(:count)
    |> case do
      0 -> []
      count -> [{:inflight_updates, count}]
    end
  end

  @doc """
  What a user should be told before deleting this firmware.

  Deltas built *from* this firmware go with it, so devices running it lose their
  small updates and fall back to downloading whole firmware. Worth saying out
  loud; not worth refusing over.
  """
  @spec deletion_warnings(Firmware.t()) :: [deletion_warning()]
  def deletion_warnings(%Firmware{} = firmware) do
    FirmwareDelta
    |> where([fd], fd.source_id == ^firmware.id)
    |> Repo.aggregate(:count)
    |> case do
      0 -> []
      count -> [{:delta_source, count}]
    end
  end

  @doc """
  Delete firmware, keeping the row and removing the file.

  This is a soft delete. `device_firmwares`, `inflight_updates` and
  `deployment_releases` all reference `firmwares` with `ON DELETE NO ACTION`, and
  the first of those holds a row for every device that has ever reported the
  firmware — so destroying the row would mean destroying the history of what
  devices ran, which is why deleting shipped firmware was impossible before.
  The row stays, marked with who deleted it and when, and only the file goes.

  Deltas referencing the firmware are deleted outright: they are derived data,
  useless without both endpoints, and their files are queued for removal too.

  Closing an account does not come through here — see
  `NervesHub.Accounts.RemoveAccount`, which destroys firmware rather than
  retiring it.
  """
  @spec delete_firmware(Firmware.t(), AuditLogs.actor() | nil) ::
          {:ok, Firmware.t()} | {:error, {:blocked, [deletion_blocker()]} | Ecto.Changeset.t()}
  def delete_firmware(%Firmware{} = firmware, actor \\ nil) do
    Repo.transact(fn ->
      with :ok <- check_deletable(firmware),
           {:ok, delta_upload_metadata} <- delete_deltas_for_firmware(firmware),
           {:ok, firmware} <- soft_delete_firmware(firmware, actor) do
        _ =
          [firmware.upload_metadata | delta_upload_metadata]
          |> Enum.filter(&uploaded_file?/1)
          |> Enum.map(&DeleteFirmware.new/1)
          |> Oban.insert_all()

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

  # Re-checked inside the transaction on purpose. Once the row survives deletion
  # the foreign keys no longer refuse anything, so this is the only thing
  # standing between a user's click and firmware that a deployment group started
  # rolling out a moment ago.
  defp check_deletable(firmware) do
    case deletion_blockers(firmware) do
      [] -> :ok
      blockers -> {:error, {:blocked, blockers}}
    end
  end

  defp delete_deltas_for_firmware(firmware) do
    query = where(FirmwareDelta, [fd], fd.source_id == ^firmware.id or fd.target_id == ^firmware.id)

    deltas = query |> select([fd], %{target_id: fd.target_id, upload_metadata: fd.upload_metadata}) |> Repo.all()

    {_count, _} = Repo.delete_all(query)

    # A deployment group's status is derived from the deltas feeding its current
    # release, and some of those just went away. The firmware being deleted is
    # skipped: it cannot be anyone's current release, or a blocker would have
    # stopped us getting here.
    deltas
    |> Enum.map(& &1.target_id)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == firmware.id))
    |> Enum.each(fn target_id ->
      {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses_by_firmware_id(target_id)
    end)

    {:ok, Enum.map(deltas, & &1.upload_metadata)}
  end

  defp soft_delete_firmware(firmware, actor) do
    firmware
    |> Repo.soft_delete_changeset()
    |> Changeset.put_change(:deleted_by_id, AuditLogs.actor_user_id(actor))
    |> Repo.update()
  end

  @spec delete_firmware_delta(FirmwareDelta.t()) ::
          {:ok, FirmwareDelta.t()} | {:error, Ecto.Changeset.t() | Oban.Job.changeset()}
  def delete_firmware_delta(%FirmwareDelta{} = delta) do
    Repo.transact(fn ->
      with {:ok, firmware} <- Repo.delete(delta),
           {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses_by_firmware_id(delta.target_id),
           :ok <- queue_file_deletion(delta.upload_metadata) do
        {:ok, firmware}
      end
    end)
  end

  defp queue_file_deletion(upload_metadata) do
    if uploaded_file?(upload_metadata) do
      with {:ok, _job} <- Oban.insert(DeleteFirmware.new(upload_metadata)), do: :ok
    else
      :ok
    end
  end

  # A delta starts with empty upload metadata and only gets a file once it is
  # built, so one that failed, timed out or is still processing has nothing to
  # delete.
  defp uploaded_file?(upload_metadata), do: upload_metadata != %{}

  @doc """
  Verify an fwup archive against a set of org keys.

  Signature checking now belongs to the update tool that recognises the archive
  — see `c:NervesHub.Firmwares.UpdateTool.verify_signature/2` — because each
  image format carries its signature differently. This remains as the fwup entry
  point; the upload path resolves the tool instead of calling it directly.
  """
  @spec verify_signature(String.t(), [OrgKey.t()]) ::
          {:ok, OrgKey.t()}
          | {:error, :invalid_signature}
          | {:error, :no_public_keys}
          | {:error, {:fwup_too_old, required :: String.t(), installed :: String.t()}}
  defdelegate verify_signature(filepath, keys), to: Fwup

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
  Translate the firmware metadata a device reported on join.

  Which keys are read depends on the device: a Nerves device reports
  `nerves_fw_*`, an ESP-IDF device reports `esp_idf_*`. The update tool owns
  that translation — see `NervesHub.Firmwares.UpdateTool.for_device_metadata/2`
  for how one is chosen.

  If the result is not a complete `FirmwareMetadata`, the reported UUID is
  looked up instead, so a device that reports little still resolves to the
  firmware NervesHub already holds.
  """
  # Returns the plain map shape (`FirmwareMetadata.metadata()`), not the struct —
  # callers feed it to `FirmwareMetadata.changeset/2`. The spec previously said
  # `FirmwareMetadata.t()`, which no code path has ever produced.
  @spec metadata_from_device(metadata :: map(), product_id :: pos_integer()) ::
          {:ok, FirmwareMetadata.metadata() | nil}
  def metadata_from_device(reported, product_id) do
    metadata =
      reported
      |> UpdateTool.for_device_metadata()
      |> then(& &1.metadata_from_device(reported))

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

    with true <- firmware.delta_updatable,
         {:ok, tool} <- UpdateTool.for_firmware(firmware) do
      :delta == tool.device_update_type(device, firmware)
    else
      _ -> false
    end
  end

  @spec delta_ready?(Device.t(), Firmware.t()) :: boolean()
  def delta_ready?(%Device{firmware_metadata: %{uuid: source_uuid}}, %Firmware{id: target_id, product_id: product_id}) do
    source_uuid
    |> firmware_delta_query(product_id, target_id)
    |> where([fd], fd.status == :completed)
    |> Repo.exists?()
  end

  @doc """
  The delta or full firmware that takes the device to `target_firmware`, which
  defaults to the deployment group's current release firmware.

  A delta is only used when the group allows them, the target supports them, and
  one from the device's running firmware is ready.
  """
  @spec get_delta_or_firmware(Device.t(), DeploymentGroup.t(), Firmware.t() | nil) ::
          {:ok, Firmware.t()} | {:ok, FirmwareDelta.t()}
  def get_delta_or_firmware(device, deployment_group, target_firmware \\ nil)

  def get_delta_or_firmware(
        device,
        %DeploymentGroup{current_release: %DeploymentRelease{firmware: %Firmware{} = target}} = deployment_group,
        nil
      ) do
    get_delta_or_firmware(device, deployment_group, target)
  end

  def get_delta_or_firmware(
        %Device{firmware_metadata: %{uuid: source_uuid}} = device,
        %DeploymentGroup{delta_updatable: true},
        %Firmware{delta_updatable: true} = target_firmware
      ) do
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

  def get_delta_or_firmware(%Device{}, %DeploymentGroup{}, %Firmware{} = target_firmware), do: {:ok, target_firmware}

  @doc """
  The delta that takes the device from the firmware it is running to `firmware`.

  Returns the delta itself rather than a URL for it, because the delta is what
  the device downloads, and so it is the delta's size and checksums that
  describe that download.
  """
  @spec get_delta(Device.t(), Firmware.t()) ::
          {:ok, FirmwareDelta.t()}
          | {:error, :not_found}
  def get_delta(%Device{firmware_metadata: %{uuid: source_uuid}}, %Firmware{id: target_id, product_id: product_id}) do
    source_uuid
    |> firmware_delta_query(product_id, target_id)
    |> Repo.fetch()
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
  # UUID to the target firmware id. Shared by delta_ready?/2 and get_delta/2.
  #
  # The source is looked up among live firmware only. A build deleted and
  # uploaded again leaves two rows carrying its uuid, and the subquery has to
  # return one. `firmwares_product_id_uuid_index` makes live firmware unique per
  # product, and deleting firmware takes its deltas with it, so the deleted row
  # has nothing to find anyway.
  defp firmware_delta_query(source_uuid, product_id, target_id) do
    source_firmware_id_query =
      Firmware
      |> where(uuid: ^source_uuid)
      |> where(product_id: ^product_id)
      |> Repo.exclude_deleted()
      |> select([f], f.id)

    FirmwareDelta
    |> where([fd], fd.source_id == subquery(source_firmware_id_query))
    |> where([fd], fd.target_id == ^target_id)
  end

  @spec generate_firmware_delta(FirmwareDelta.t(), Firmware.t(), Firmware.t()) ::
          :ok
          | {:error, Ecto.Changeset.t() | :no_delta_support_in_firmware}
  def generate_firmware_delta(firmware_delta, source_firmware, target_firmware) do
    # Whether deltas are *wanted* is a deployment group setting, and whether a
    # particular archive can be patched is `delta_updatable` on the firmware,
    # checked when an update is sent. Neither answers whether the format can be
    # patched at all.
    #
    # Every format currently shipped answers yes, so this reads as a formality.
    # It is not: a format arrives without an applier, not with one — ESP-IDF
    # spent two releases here answering no — and the cost of asking late is a
    # patch built and stored that nothing can ever use. Asked here as well as in
    # `attempt_firmware_delta/3` because a job queued before a format changed
    # its answer arrives straight at this function.
    if delta_capable_format?(target_firmware) do
      do_generate_firmware_delta(firmware_delta, source_firmware, target_firmware)
    else
      Logger.info("Skipping delta for #{target_firmware.uuid}: #{target_firmware.tool} images cannot be patched.")

      {:error, :no_delta_support_in_firmware}
    end
  end

  defp do_generate_firmware_delta(firmware_delta, source_firmware, target_firmware) do
    {:ok, work_dir} = Briefly.create(type: :directory)

    Logger.info("Creating firmware delta between #{source_firmware.uuid} and #{target_firmware.uuid}.")

    {:ok, source_url} = firmware_upload_config().download_file(source_firmware)
    {:ok, target_url} = firmware_upload_config().download_file(target_firmware)

    with {:ok, tool} <- UpdateTool.for_firmware(target_firmware),
         {:ok, delta_file_metadata} <-
           tool.create_firmware_delta_file(
             {source_firmware.uuid, source_url},
             {target_firmware.uuid, target_url},
             work_dir
           ) do
      case finalize_delta(firmware_delta, source_firmware, target_firmware, delta_file_metadata) do
        {:ok, _delta} ->
          :ok

        # Nothing left to mark failed
        {:error, :delta_deleted} = error ->
          error

        {:error, err} ->
          _ = fail_firmware_delta(firmware_delta)
          {:error, err}
      end
    else
      {:error, _} = error -> error
    end
  after
    Briefly.cleanup()
  end

  defp finalize_delta(firmware_delta, source_firmware, target_firmware, delta_file_metadata) do
    # Not a hard match: an unrecognised `tool` column (a format removed from the
    # build, or corrupt data) should fail the delta rather than raise inside the
    # worker.
    with {:ok, tool} <- UpdateTool.for_firmware(target_firmware) do
      finalize_delta(firmware_delta, source_firmware, target_firmware, delta_file_metadata, tool)
    end
  end

  defp finalize_delta(firmware_delta, source_firmware, target_firmware, delta_file_metadata, tool) do
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

    # Uploaded before it is marked complete. A completed delta is offered to
    # devices straight away, and the builder takes one as done, so a delta
    # marked complete whose upload then crashed stayed complete with no file.
    with :ok <- firmware_upload_config().upload_file(delta_file_metadata.filepath, upload_metadata),
         {:ok, firmware_delta} <- complete_delta(changeset),
         {:ok, _firmware_delta} <- notify_firmware_delta_target({:ok, firmware_delta}) do
      {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses_by_firmware_id(firmware_delta.target_id)

      Logger.info("Created firmware delta successfully.")

      :ok = tool.cleanup_firmware_delta_files(delta_file_metadata.filepath)

      {:ok, firmware_delta}
    else
      # Its firmware was deleted during the upload, taking the row. That delete
      # queued no file removal, because the row did not point at the file yet.
      {:error, :delta_deleted} = error ->
        Logger.info("Firmware delta was deleted while uploading, removing its file.")

        {:ok, _} = Oban.insert(DeleteFirmware.new(upload_metadata))

        :ok = tool.cleanup_firmware_delta_files(delta_file_metadata.filepath)

        error

      {:error, error} ->
        Logger.error("Failed when finalizing firmware delta: #{inspect(error)}")

        :ok = tool.cleanup_firmware_delta_files(delta_file_metadata.filepath)

        {:error, error}
    end
  end

  defp complete_delta(changeset) do
    case Repo.update(changeset, stale_error_field: :id) do
      {:error, %Ecto.Changeset{errors: [id: {_, [stale: true]}]}} -> {:error, :delta_deleted}
      result -> result
    end
  end

  defp with_product(query) do
    query
    |> join(:left, [f], p in assoc(f, :product))
    |> preload([d, p], product: p)
  end

  @doc """
  Whether this firmware's format can be delta updated at all.

  Distinct from the `delta_updatable` flag on the firmware, which answers for
  one archive. This answers for the format, and a format that cannot be patched
  answers no however anything is configured.
  """
  @spec delta_capable_format?(Firmware.t()) :: boolean()
  def delta_capable_format?(firmware) do
    case UpdateTool.for_firmware(firmware) do
      {:ok, tool} -> tool.supports_deltas?()
      {:error, _} -> false
    end
  end

  @spec attempt_firmware_delta(
          source_id :: non_neg_integer(),
          target_id :: non_neg_integer(),
          recalculate_deployment_statuses :: boolean()
        ) ::
          {:ok, :started}
          | {:ok, :no_delta_support}
          | {:ok, :delta_already_exists}
          | {:error, :failed_to_insert_delta}
          | {:error, :failed_to_insert_job}
  def attempt_firmware_delta(source_id, target_id, recalculate_deployment_statuses \\ true) do
    # Nothing is recorded for a format that cannot be patched, because nothing
    # was attempted. Starting one and failing it reads in the UI as "Deltas
    # failed to generate", which describes a broken build rather than a
    # deployment group doing exactly what it should.
    if delta_capable_format?(get_firmware!(target_id)) do
      do_attempt_firmware_delta(source_id, target_id, recalculate_deployment_statuses)
    else
      {:ok, :no_delta_support}
    end
  end

  @doc """
  Build a failed or timed-out delta again.

  Starting it replaces the failed delta in the same transaction. Deleted first
  on its own, the delta's release was left with nothing failed and nothing
  building, which reads as ready, and the orchestrator sent full firmware to the
  devices waiting for the delta.
  """
  @spec retry_firmware_delta(FirmwareDelta.t()) ::
          {:ok, :started}
          | {:ok, :no_delta_support}
          | {:ok, :delta_already_exists}
          | {:error, :failed_to_insert_delta}
          | {:error, :failed_to_insert_job}
  def retry_firmware_delta(%FirmwareDelta{source_id: source_id, target_id: target_id}) do
    attempt_firmware_delta(source_id, target_id)
  end

  defp do_attempt_firmware_delta(source_id, target_id, recalculate_deployment_statuses) do
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

        # Started by another caller since the look above.
        {:delta_insert, {:error, :already_exists}} ->
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

  @doc """
  Start building a delta, replacing one that failed or timed out.

  Returns `{:error, :already_exists}` when another caller started it first.
  Devices added to a deployment group together race to start the same delta,
  usually inside the transaction that adds them, so losing the race must not
  abort that transaction. The losing insert waits for the winner to commit and
  then does nothing, where a unique violation would have aborted it.
  """
  @spec start_firmware_delta(non_neg_integer(), non_neg_integer(), boolean()) ::
          {:ok, FirmwareDelta.t()} | {:error, :already_exists} | {:error, Ecto.Changeset.t()}
  def start_firmware_delta(source_id, target_id, recalculate_deployment_statuses \\ true) do
    # Both racing callers can find the same failed delta, so this must not
    # raise when the other has already deleted it.
    {_deleted, _} =
      FirmwareDelta
      |> where([fd], fd.source_id == ^source_id and fd.target_id == ^target_id)
      |> where([fd], fd.status in [:failed, :timed_out])
      |> Repo.delete_all()

    %FirmwareDelta{}
    |> FirmwareDelta.start_changeset(source_id, target_id)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:source_id, :target_id])
    |> case do
      {:ok, %FirmwareDelta{id: nil}} ->
        {:error, :already_exists}

      {:ok, firmware_delta} ->
        :ok = PubSub.broadcast_delta_status(firmware_delta)

        _ =
          if recalculate_deployment_statuses do
            {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses_by_firmware_id(target_id)
          end

        {:ok, firmware_delta}

      {:error, _changeset} = error ->
        error
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

    {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses_by_firmware_id(firmware_delta.target_id)

    {:ok, firmware_delta}
  end

  @doc """
  Time out a delta whose build has taken too long.

  Only a delta still processing is timed out. The sweep reads its deltas before
  it writes them, and writing back the copy it read turned a delta whose build
  finished in between into a timed-out one.
  """
  @spec time_out_firmware_delta(FirmwareDelta.t()) :: {:ok, FirmwareDelta.t()} | {:error, :not_processing}
  def time_out_firmware_delta(%FirmwareDelta{id: id}) do
    FirmwareDelta
    |> where([fd], fd.id == ^id and fd.status == :processing)
    |> select([fd], fd)
    |> Repo.update_all(set: [status: :timed_out, updated_at: NaiveDateTime.utc_now(:second)])
    |> case do
      {1, [firmware_delta]} ->
        {:ok, firmware_delta} = notify_firmware_delta_target({:ok, firmware_delta})

        {:ok, _} =
          ManagedDeployments.recalculate_release_delta_statuses_by_firmware_id(firmware_delta.target_id)

        {:ok, firmware_delta}

      {0, []} ->
        {:error, :not_processing}
    end
  end

  # Pipeline adapter for the delta lifecycle functions above, which all thread an
  # `{:ok, delta} | {:error, term()}` through. The transport lives in
  # `NervesHub.Firmwares.PubSub`.
  defp notify_firmware_delta_target({:ok, %FirmwareDelta{} = firmware_delta}) do
    :ok = PubSub.broadcast_delta_status(firmware_delta)

    {:ok, firmware_delta}
  end

  defp notify_firmware_delta_target(error), do: error

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
      # `{:error, :not_processing}` when its build finished since the read above
      _ = time_out_firmware_delta(firmware_delta)
    end)

    :ok
  end

  @spec build_firmware_params(Org.t(), Path.t(), Product.t() | nil) :: {:ok, map()} | {:error, any()}
  defp build_firmware_params(%{id: org_id} = org, filepath, expected_product) do
    org = NervesHub.Repo.preload(org, :org_keys)

    with {:ok, tool} <- UpdateTool.for_file(filepath),
         :ok <- check_tool_allowed(tool, expected_product),
         {:ok, org_key} <- verify_signature(tool, filepath, org.org_keys, expected_product),
         {:ok, %{firmware_metadata: fm, tool_metadata: tm} = m} <-
           tool.get_firmware_metadata_from_file(filepath),
         :ok <- check_expected_product(fm.product, expected_product) do
      filename = fm.uuid <> tool.file_extension()

      params =
        %{
          architecture: fm.architecture,
          author: fm.author,
          description: fm.description,
          filename: filename,
          filepath: filepath,
          misc: fm.misc,
          org_id: org_id,
          org_key_id: org_key && org_key.id,
          delta_updatable: tool.delta_updatable?(m),
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
        |> resolve_product(expected_product)

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

  # The archive declares which product it belongs to. When the upload was
  # addressed to a particular product, that has already been checked to match
  # (see `check_expected_product/2`), so it can be used directly rather than
  # looked up a second time.
  defp resolve_product(params, %Product{} = product) do
    params
    |> Map.put(:product_id, product.id)
    |> Map.put(:require_unique_firmware_version, product.require_unique_firmware_version)
  end

  defp resolve_product(params, nil) do
    case Products.get_product_by_org_id_and_name(params.org_id, params.product_name) do
      {:ok, product} ->
        params
        |> Map.put(:product_id, product.id)
        |> Map.put(:require_unique_firmware_version, product.require_unique_firmware_version)

      _ ->
        params
    end
  end

  # A product accepts only the formats it opted into. Checked before the
  # signature, so an uploader hears "this product does not take ESP-IDF images"
  # rather than a complaint about the signing of a format it will not take.
  defp check_tool_allowed(_tool, nil), do: :ok

  defp check_tool_allowed(tool, %Product{} = product) do
    if Product.accepts_update_tool?(product, tool.tool_name()) do
      :ok
    else
      {:error, {:update_tool_not_allowed, tool.tool_name(), product.name}}
    end
  end

  # A product may accept unsigned images for a format that can arrive that way:
  # most ESP-IDF builds are not signed, and nothing but `nh-avm` signs a
  # packbeam. A *present but invalid* signature is still refused — the setting
  # excuses the absence of a signature, never a bad one.
  defp verify_signature(tool, filepath, org_keys, product) do
    case tool.verify_signature(filepath, org_keys) do
      {:error, :firmware_not_signed} ->
        if unsigned_allowed?(tool, product) do
          {:ok, nil}
        else
          {:error, :firmware_not_signed}
        end

      result ->
        result
    end
  end

  # Per format, because they are unsigned for unrelated reasons and a product
  # may reasonably allow one and not the other. fwup is absent on purpose: an
  # fwup archive is always verified.
  defp unsigned_allowed?(tool, %Product{} = product) do
    case tool.tool_name() do
      "esp-idf" -> product.allow_unsigned_esp_idf_firmware
      "atomvm" -> product.allow_unsigned_atomvm_firmware
      _other -> false
    end
  end

  defp unsigned_allowed?(_tool, _product), do: false

  # Uploading to `/products/a/firmware` an archive that declares product "b"
  # used to file the firmware under "b" and hand back a `location` header
  # pointing at "a" — a link to something that is not there. The upload target
  # wins, and a mismatch is refused rather than silently rerouted.
  defp check_expected_product(_declared, nil), do: :ok
  defp check_expected_product(declared, %Product{name: declared}), do: :ok

  defp check_expected_product(declared, %Product{name: expected}) do
    {:error, {:product_mismatch, declared, expected}}
  end
end
