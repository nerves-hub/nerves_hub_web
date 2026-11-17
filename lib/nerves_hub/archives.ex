defmodule NervesHub.Archives do
  @moduledoc """
  Archives are extra fwup files that will be delivered to the device on connect

  ## Where the files are stored

  An archive's file is stored at `/archives/<org id>/<product id>/<uuid>.fw`,
  and the archive keeps that path as its `storage_key`. The UUID comes from the
  uploaded file, so whoever builds an archive chooses it. Only the org and
  product in the path keep one org's archive from landing on another's.

  Archives uploaded before that have no `storage_key`. Their files stay at
  `/archives/<uuid>.fw`, where they were uploaded, and are served and deleted
  from there. Two of these with the same UUID share one file. Nothing new is
  ever written to that path.

  A file is only deleted once no archive uses its path, which also covers an
  archive deleted and uploaded again before its old file was removed.
  """

  import Ecto.Query

  alias NervesHub.Archives.Archive
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Fwup
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Workers.DeleteArchive

  @spec get_by_id(Product.t(), pos_integer()) :: Archive.t() | nil
  def get_by_id(_product, archive_id) when archive_id in [nil, ""], do: nil

  def get_by_id(%Product{} = product, archive_id) do
    Archive
    |> where([f], f.product_id == ^product.id)
    |> where([f], f.id == ^archive_id)
    |> Repo.one()
  end

  @typedoc """
  Which of a product's archives the archive list shows.

  `:delivered` is an archive in some deployment group's current release, which
  is the only way an archive reaches devices; `:not_delivered` is the rest.
  """
  @type list_tab() :: :all | :delivered | :not_delivered

  @type list_opts() :: %{
          optional(:tab) => list_tab(),
          optional(:search) => String.t() | nil,
          optional(:platform) => String.t() | nil,
          optional(:sort) => String.t(),
          optional(:sort_direction) => String.t(),
          optional(:page) => String.t() | pos_integer(),
          optional(:page_size) => String.t() | pos_integer()
        }

  @list_sorts ~w(inserted_at version)

  @doc """
  A page of the product's archives, for the archive list.

  `opts` picks the tab (see `t:list_tab/0`), narrows by `search` (part of a
  description, or the start of a version, UUID or VCS identifier) and
  `platform`, and sorts by `inserted_at` (the default) or `version`. A page
  holds 25 archives unless `page_size` says otherwise, and never more than 100.
  """
  @spec list_archives(Product.t(), list_opts()) :: {[Archive.t()], Flop.Meta.t()}
  def list_archives(%Product{} = product, opts \\ %{}) do
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) or val == "" end)

    sort = if opts[:sort] in @list_sorts, do: opts[:sort], else: "inserted_at"
    sort_direction = if opts[:sort_direction] == "asc", do: :asc, else: :desc

    flop = %Flop{
      page: to_positive_integer(opts[:page], 1),
      # The pager offers 25, 50 and 100. Anything bigger only comes from an
      # edited URL, so it is held to the largest of those.
      page_size: min(to_positive_integer(opts[:page_size], 25), 100)
    }

    Archive
    |> from(as: :archive)
    |> where([archive: a], a.product_id == ^product.id)
    |> where_tab(Map.get(opts, :tab, :all))
    |> where_search(opts[:search])
    |> where_platform(opts[:platform])
    |> sort_archives({sort_direction, String.to_existing_atom(sort)})
    |> Flop.run(flop)
  end

  @doc """
  How many of the product's archives each tab of the archive list holds.
  """
  @spec list_counts(Product.t()) :: %{
          all: non_neg_integer(),
          delivered: non_neg_integer(),
          not_delivered: non_neg_integer()
        }
  def list_counts(%Product{} = product) do
    counts =
      Archive
      |> from(as: :archive)
      |> where([archive: a], a.product_id == ^product.id)
      |> select([archive: a], %{
        all: count(a.id),
        delivered: filter(count(a.id), exists(current_release_with_query()))
      })
      |> Repo.one()

    Map.put(counts, :not_delivered, counts.all - counts.delivered)
  end

  @doc """
  The platforms of the product's archives, in order, for the platform filter.
  """
  @spec platforms(Product.t()) :: [String.t()]
  def platforms(%Product{} = product) do
    Archive
    |> where([a], a.product_id == ^product.id)
    |> distinct(true)
    |> select([a], a.platform)
    |> order_by([a], a.platform)
    |> Repo.all()
  end

  @doc """
  Every deployment release of the product that includes each of the given
  archives, keyed by archive id.

  Each release carries its deployment group and firmware, whether it is the
  group's current release, and when the group's next release replaced it
  (`nil` while it is current). Current releases come first, then the rest
  newest first.

  Any of these releases, past ones included, stops the archive being deleted:
  a group's history keeps the archive it shipped with.
  """
  @spec releases(Product.t(), [pos_integer()]) :: %{
          pos_integer() => [
            %{
              deployment_group: DeploymentGroup.t(),
              firmware: Firmware.t(),
              current?: boolean(),
              released_at: NaiveDateTime.t(),
              replaced_at: NaiveDateTime.t() | nil
            }
          ]
        }
  def releases(_product, []), do: %{}

  def releases(%Product{} = product, archive_ids) do
    DeploymentRelease
    |> join(:inner, [dr], dg in assoc(dr, :deployment_group))
    |> join(:inner, [dr], f in assoc(dr, :firmware))
    |> join(:left, [dr], next in DeploymentRelease,
      on: next.deployment_group_id == dr.deployment_group_id and next.number == dr.number + 1
    )
    |> where([dr, dg], dr.archive_id in ^archive_ids and dg.product_id == ^product.id)
    |> select([dr, dg, f, next], %{
      archive_id: dr.archive_id,
      deployment_group: dg,
      firmware: f,
      current?: dg.current_deployment_release_id == dr.id,
      released_at: dr.inserted_at,
      replaced_at: next.inserted_at
    })
    |> Repo.all()
    # Both sorts are stable, so the current releases end up first and each
    # half stays newest first.
    |> Enum.sort_by(& &1.released_at, {:desc, NaiveDateTime})
    |> Enum.sort_by(&(not &1.current?))
    |> Enum.group_by(& &1.archive_id, &Map.delete(&1, :archive_id))
  end

  @doc """
  Who an archive reaches, for the archive's page.

  An archive is sent to a device in a deployment group whose current release
  includes it, once the device runs that release's firmware (see
  `archive_for_deployment_group/2`). For each such group this counts its
  devices and how many get the archive now; the rest get it after they update.
  `:gets_it_now` and `:gets_it_after_updating` add those up across the groups.
  """
  @spec delivery(Archive.t()) :: %{
          groups: [
            %{
              deployment_group: DeploymentGroup.t(),
              firmware: Firmware.t(),
              devices: non_neg_integer(),
              gets_it: non_neg_integer()
            }
          ],
          gets_it_now: non_neg_integer(),
          gets_it_after_updating: non_neg_integer()
        }
  def delivery(%Archive{} = archive) do
    groups =
      DeploymentGroup
      |> join(:inner, [dg], cr in assoc(dg, :current_release))
      |> join(:inner, [_dg, cr], f in assoc(cr, :firmware))
      |> join(:left, [dg], d in Device, on: d.deployment_id == dg.id and is_nil(d.deleted_at))
      |> where([_dg, cr], cr.archive_id == ^archive.id)
      |> group_by([dg, _cr, f], [dg.id, f.id])
      |> select([dg, _cr, f, d], %{
        deployment_group: dg,
        firmware: f,
        devices: count(d.id),
        gets_it: filter(count(d.id), fragment("? ->> 'uuid'", d.firmware_metadata) == f.uuid)
      })
      |> order_by([dg], dg.name)
      |> Repo.all()

    %{
      groups: groups,
      gets_it_now: groups |> Enum.map(& &1.gets_it) |> Enum.sum(),
      gets_it_after_updating: groups |> Enum.map(&(&1.devices - &1.gets_it)) |> Enum.sum()
    }
  end

  defp current_release_with_query() do
    DeploymentGroup
    |> join(:inner, [dg], cr in assoc(dg, :current_release))
    |> where([_dg, cr], cr.archive_id == parent_as(:archive).id)
    |> select(1)
  end

  defp where_tab(query, :delivered), do: where(query, exists(current_release_with_query()))
  defp where_tab(query, :not_delivered), do: where(query, not exists(current_release_with_query()))
  defp where_tab(query, _all), do: query

  defp where_search(query, nil), do: query

  defp where_search(query, search) do
    escaped = escape_like(String.trim(search))
    prefix = escaped <> "%"
    anywhere = "%" <> escaped <> "%"

    where(
      query,
      [archive: a],
      ilike(a.description, ^anywhere) or ilike(a.version, ^prefix) or
        ilike(type(a.uuid, :string), ^prefix) or ilike(a.vcs_identifier, ^prefix)
    )
  end

  defp where_platform(query, nil), do: query
  defp where_platform(query, platform), do: where(query, [archive: a], a.platform == ^platform)

  # `%` and `_` are wildcards to `ilike`, and a version can hold an underscore.
  defp escape_like(search) do
    String.replace(search, ~r/([\\%_])/, "\\\\\\1")
  end

  # Versions sort by SemVer precedence: see `NervesHub.Firmwares` for why the
  # sort key needs `COLLATE "C"`.
  defp sort_archives(query, {direction, :version}) do
    nulls = if direction == :asc, do: :asc_nulls_last, else: :desc_nulls_last

    order_by(query, [archive: a], [
      {^nulls, fragment(~s|semver_sort_key(?) COLLATE "C"|, a.version)},
      desc: a.inserted_at
    ])
  end

  defp sort_archives(query, {direction, field}), do: order_by(query, ^[{direction, field}, desc: :id])

  defp to_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp to_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _ -> default
    end
  end

  defp to_positive_integer(_value, default), do: default

  @spec all_by_product(Product.t()) :: [Archive.t()]
  def all_by_product(product) do
    Archive
    |> where([a], a.product_id == ^product.id)
    |> Repo.all()
  end

  @spec get(Product.t(), String.t()) :: {:ok, Archive.t()} | {:error, :not_found}
  def get(product, uuid) when is_binary(uuid) do
    Archive
    |> where([a], a.uuid == ^uuid)
    |> where([a], a.product_id == ^product.id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      archive ->
        {:ok, Repo.preload(archive, product: [:org])}
    end
  end

  @spec get_by_product_and_uuid!(Product.t(), String.t()) :: Archive.t()
  def get_by_product_and_uuid!(product, uuid) do
    Archive
    |> where(uuid: ^uuid)
    |> where(product_id: ^product.id)
    |> join(:inner, [a], p in assoc(a, :product))
    |> join(:inner, [a, p], o in assoc(p, :org))
    |> preload([a, p, o], product: {p, org: o})
    |> Repo.one!()
  end

  @doc """
  The archive a device should have from its deployment group, if any.

  An archive belongs to the release it was added to, so only a device already
  running the current release's firmware is sent one. A device working its way
  through a required release gets it on the connection after it lands on the
  current release.
  """
  @spec archive_for_deployment_group(integer() | nil, String.t() | nil) :: Archive.t() | nil
  def archive_for_deployment_group(deployment_id, firmware_uuid)

  def archive_for_deployment_group(nil, _firmware_uuid), do: nil

  def archive_for_deployment_group(_deployment_id, nil), do: nil

  def archive_for_deployment_group(deployment_id, firmware_uuid) do
    Archive
    |> join(:inner, [a], dr in DeploymentRelease, on: dr.archive_id == a.id)
    |> join(:inner, [a, dr], dg in DeploymentGroup, on: dr.id == dg.current_deployment_release_id)
    |> join(:inner, [a, dr], f in Firmware, on: f.id == dr.firmware_id)
    |> where([a, _dr, dg], dg.id == ^deployment_id)
    |> where([a, _dr, _dg, f], f.uuid == ^firmware_uuid)
    |> Repo.one()
  end

  # TODO: check on other return signatures
  @spec create(Product.t(), String.t()) ::
          {:ok, Archive.t()}
          | {:error, :invalid_signature}
          | {:error, :no_public_keys}
          | {:error, {:fwup_too_old, required :: String.t(), installed :: String.t()}}
          | {:error, any()}
          | {:error, {any(), :not_found}}
  def create(product, file_path) do
    product = Repo.preload(product, org: [:org_keys])

    with {:ok, org_key} <- UpdateTool.Fwup.verify_signature(file_path, product.org.org_keys),
         {:ok, metadata} <- Fwup.metadata(file_path),
         {:ok, archive} <-
           product
           |> Ecto.build_assoc(:archives)
           |> Map.put(:org_key_id, org_key.id)
           |> Map.put(:size, :filelib.file_size(file_path))
           |> Archive.create_changeset(metadata)
           |> put_storage_key(product)
           |> Repo.insert() do
      NervesHub.Uploads.upload(file_path, archive_path(archive))

      {:ok, archive}
    end
  end

  @spec delete_archive(Archive.t()) :: {:ok, Archive.t()} | {:error, any()}
  def delete_archive(%Archive{} = archive) do
    Repo.transact(fn ->
      with {:ok, archive} <- Repo.delete(Archive.delete_changeset(archive)),
           {:ok, _} <- delete_artifacts(archive) do
        {:ok, archive}
      end
    end)
  end

  defp delete_artifacts(archive) do
    %{archive_path: archive_path(archive)}
    |> DeleteArchive.new()
    |> Oban.insert()
  end

  @spec url(Archive.t()) :: String.t()
  def url(archive) do
    NervesHub.Uploads.url(archive_path(archive), signed: [expires_in: 3600])
  end

  @doc """
  Whether any archive's file is stored at `path`, so deleting it would take the
  file from under that archive.

  Asked when the file is about to be deleted, rather than when its archive was,
  so an archive uploaded again in between keeps its file.
  """
  @spec file_in_use?(String.t()) :: boolean()
  def file_in_use?(path) when is_binary(path) do
    query = where(Archive, [a], a.storage_key == ^path)

    query =
      case legacy_uuid(path) do
        {:ok, uuid} -> or_where(query, [a], is_nil(a.storage_key) and a.uuid == ^uuid)
        :error -> query
      end

    Repo.exists?(query)
  end

  defp put_storage_key(changeset, product) do
    case Ecto.Changeset.get_field(changeset, :uuid) do
      nil -> changeset
      uuid -> Ecto.Changeset.put_change(changeset, :storage_key, "/archives/#{product.org_id}/#{product.id}/#{uuid}.fw")
    end
  end

  defp archive_path(%Archive{storage_key: nil, uuid: uuid}), do: legacy_path(uuid)
  defp archive_path(%Archive{storage_key: storage_key}), do: storage_key

  defp legacy_path(uuid), do: "/archives/#{uuid}.fw"

  defp legacy_uuid("/archives/" <> name) do
    if String.ends_with?(name, ".fw") do
      name |> String.trim_trailing(".fw") |> Ecto.UUID.cast()
    else
      :error
    end
  end

  defp legacy_uuid(_path), do: :error
end
