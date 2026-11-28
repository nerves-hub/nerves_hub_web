defmodule NervesHub.Devices do
  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.PubSub, as: AccessPubSub
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.AuditLogs.Template
  alias NervesHub.DeviceEvents
  alias NervesHub.DeviceLink
  alias NervesHub.Devices.AdvancedQuery
  alias NervesHub.Devices.Certificates
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.DeviceFiltering
  alias NervesHub.Devices.DeviceFirmwares
  alias NervesHub.Devices.NetworkIdentity
  alias NervesHub.Devices.PinnedDevice
  alias NervesHub.Devices.SharedSecretAuth
  alias NervesHub.Devices.Updates
  alias NervesHub.Devices.Visibility
  alias NervesHub.Extensions
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.ManagedDeployments.InflightDeploymentCheck
  alias NervesHub.ProductNotifications
  alias NervesHub.Products
  alias NervesHub.Products.ApiKey
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Types.Tag

  @doc """
  Pair counted analytics results with their devices, in the order given.

  Analytics tables hold device ids, not devices, so a "top N devices by
  something" read comes back as `[%{device_id: _, count: _}]` and needs the
  devices fetched from PostgreSQL. The analytics ordering is preserved, and an
  id with no matching device — deleted, or belonging to another product — is
  dropped rather than rendered as a hole.
  """
  @spec with_counts([%{device_id: pos_integer(), count: non_neg_integer()}], Product.t()) ::
          [{Device.t(), non_neg_integer()}]
  def with_counts([], _product), do: []

  def with_counts(counted, %Product{id: product_id}) do
    device_ids = Enum.map(counted, & &1.device_id)

    devices =
      Device
      |> where(product_id: ^product_id)
      |> where([d], d.id in ^device_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    Enum.flat_map(counted, fn %{device_id: device_id, count: count} ->
      case Map.get(devices, device_id) do
        nil -> []
        device -> [{device, count}]
      end
    end)
  end

  def get_device(device_id) when is_integer(device_id) do
    Repo.get(Device, device_id)
  end

  def get_device(device_id, preloads \\ []) do
    Device
    |> where(id: ^device_id)
    |> join_and_preload(preloads)
    |> Repo.one!()
  end

  def get_complete_device(device_id) do
    Device
    |> where([d], d.id == ^device_id)
    |> join(:left, [d], o in assoc(d, :org))
    |> join(:left, [d, o], p in assoc(d, :product))
    |> join(:left, [d, o, p], dg in assoc(d, :deployment_group))
    |> join(:left, [d, o, p, dg], cr in assoc(dg, :current_release))
    |> join(:left, [d, o, p, dg, cr], f in assoc(cr, :firmware))
    |> join(:left, [d, o, p, dg, cr, f], lc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:left, [d, o, p, dg, cr, f, lc], lh in assoc(d, :latest_health), as: :latest_health)
    |> preload([d, o, p, dg, cr, f, latest_connection: lc, latest_health: lh],
      org: o,
      product: p,
      deployment_group: {dg, current_release: {cr, firmware: f}},
      latest_connection: lc,
      latest_health: lh
    )
    |> Repo.exclude_deleted()
    |> Repo.one()
  end

  def get_active_device(filters) do
    Device
    |> Repo.exclude_deleted()
    |> join(:inner, [d], p in assoc(d, :product))
    |> preload([_d, p], product: p)
    |> Repo.get_by(filters)
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_devices_by_org_id_and_product_id(org_id, product_id) do
    Device
    |> where([d], d.org_id == ^org_id)
    |> where([d], d.product_id == ^product_id)
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  def get_devices_by_org_id_and_product_id(org_id, product_id, opts) do
    {entries, _pager} = get_devices_by_org_id_and_product_id_with_pager(org_id, product_id, opts)
    entries
  end

  @doc """
  The API's devices list: a page of the product's devices that `opts[:visible_to]`
  can see, filtered and sorted as `filter/3` would, 10 to a page by default.

  Soft-deleted devices are left out unless the `display_deleted` filter is
  `"include"`, which lists them too, or `"only"`, which lists them alone. An
  advanced query that names `deleted` decides instead.
  """
  def get_devices_by_org_id_and_product_id_with_pager(org_id, product_id, opts) do
    pagination = Map.merge(%{page: 1, page_size: 10}, Map.get(opts, :pagination, %{}))
    flop = %Flop{page: pagination[:page], page_size: pagination[:page_size]}
    opts = Map.put(opts, :filters, display_deleted_by_default(opts[:filters] || %{}))

    {devices, meta} =
      opts[:visible_to]
      |> list_query()
      |> where([device: d], d.org_id == ^org_id)
      |> filter_list(product_id, opts)
      |> Flop.run(flop)

    # What `NervesHubWeb.API.DeviceJSON` shows.
    devices =
      Repo.preload(devices, [
        :org,
        :product,
        :latest_connection,
        deployment_group: [current_release: :firmware]
      ])

    {devices, meta}
  end

  # The web UI always sends `display_deleted`; an API request may leave it out
  # or send anything, so all but "include" and "only" mean "exclude".
  defp display_deleted_by_default(%{display_deleted: value} = filters) when value in ["include", "only"], do: filters
  defp display_deleted_by_default(filters), do: Map.put(filters, :display_deleted, "exclude")

  def get_device_count_by_org_id_and_product_id(org_id, product_id) do
    query =
      from(
        d in Device,
        select: count(d.id),
        where: d.org_id == ^org_id,
        where: d.product_id == ^product_id
      )

    query
    |> Repo.one!()
  end

  @doc """
  The web UI's devices list: a page of `filter_query/3`, 25 to a page by
  default, with what the list's rows show loaded.
  """
  @spec filter(Product.t(), User.t(), map()) :: {[Device.t()], Flop.Meta.t()}
  def filter(product, user, opts) do
    pagination = Map.get(opts, :pagination, %{})
    flop = %Flop{page: Map.get(pagination, :page, 1), page_size: Map.get(pagination, :page_size, 25)}

    {devices, meta} =
      product
      |> filter_query(user, opts)
      |> Flop.run(flop)

    # The firmware is what the list's Firmware column measures each device
    # against: its group's release (up to date, waiting, failing to take it)
    # and the firmware an update in progress is installing.
    devices =
      Repo.preload(devices, [
        :latest_connection,
        :latest_health,
        deployment_group: [current_release: :firmware],
        inflight_update: :firmware
      ])

    {devices, meta}
  end

  @doc """
  Every device in the product that the user can see and `opts`' filters
  match, sorted by `opts[:sort]` (identifier by default), with nothing loaded
  but the devices.

  `filter/3` pages it, and the devices list's counts, bulk actions and export
  start from it.
  """
  @spec filter_query(Product.t(), User.t(), map()) :: Ecto.Query.t()
  def filter_query(product, user, opts) do
    user
    |> list_query()
    |> join_pinned(user)
    |> filter_list(product.id, opts)
  end

  @doc """
  How many of the devices `filter/3` would list fall in each of the devices
  list's tabs, keyed `"all"` and by `DeviceFiltering.states/0`, and in each
  of the Needs attention tab's reasons, keyed by `DeviceFiltering.reasons/0`.

  Counted with the rest of `opts`' filters applied but not its `:state` or
  `:reason`, so every tab and reason shows how many devices it would list if
  picked. A device can need attention for more than one reason, so the
  reasons can add up to more than the tab. One query.
  """
  @spec state_counts(Product.t(), User.t(), map()) :: %{String.t() => non_neg_integer()}
  def state_counts(product, user, opts) do
    opts = Map.update(opts, :filters, %{}, &Map.drop(&1, [:state, :reason]))

    product
    |> filter_query(user, opts)
    |> count_states()
  end

  # `state_counts/3` of a query built without a tab or reason.
  defp count_states(query) do
    conditions =
      Enum.map(DeviceFiltering.states(), &{&1, DeviceFiltering.state_dynamic(&1)}) ++
        Enum.map(DeviceFiltering.reasons(), &{&1, DeviceFiltering.reason_dynamic(&1)})

    counts =
      Map.new(conditions, fn {key, condition} ->
        {key, dynamic([device: d], filter(count(d.id), ^condition))}
      end)

    query
    |> exclude(:order_by)
    |> select(^Map.put(counts, "all", dynamic([device: d], count(d.id))))
    |> Repo.one()
  end

  @doc """
  For each of `facets`' multi-choice filters (`DeviceFiltering.multi_filters/0`),
  how many devices each of its choices would list with the rest of `opts`'
  filters applied: what picking that choice alone would give.

  `facets` maps each filter to the choices to count. One query per filter.
  """
  @spec facet_counts(Product.t(), User.t(), map(), %{atom() => [String.t()]}) ::
          %{atom() => %{String.t() => non_neg_integer()}}
  def facet_counts(product, user, opts, facets) do
    Map.new(facets, fn {key, choices} ->
      {key, count_facet(key, choices, product, user, put_in(opts, [:filters, key], ""))}
    end)
  end

  # One `count(...) FILTER` per version re-reads every device once per
  # version, and a product can have 100+ versions. Grouping reads each device
  # once. Choices match as in `DeviceFiltering.value_dynamic/2`: "Unknown" is
  # a NULL version, and any other choice is an exact version match.
  defp count_facet(:firmware_version, choices, product, user, opts) do
    groups =
      product
      |> filter_query(user, opts)
      |> exclude(:order_by)
      |> group_by([device: d], d.firmware_metadata["version"])
      |> select([device: d], {
        d.firmware_metadata["version"],
        is_nil(d.firmware_metadata["version"]),
        count(d.id)
      })
      |> Repo.all()

    Map.new(choices, fn
      "Unknown" ->
        {"Unknown", Enum.sum(for {_version, true, count} <- groups, do: count)}

      choice ->
        {choice, Enum.sum(for {^choice, false, count} <- groups, do: count)}
    end)
  end

  defp count_facet(key, choices, product, user, opts) do
    counts =
      Enum.flat_map(choices, fn choice ->
        case DeviceFiltering.value_dynamic(key, choice) do
          nil -> []
          condition -> [{choice, dynamic([device: d], filter(count(d.id), ^condition))}]
        end
      end)

    count_choices(product, user, opts, Map.new(counts))
  end

  defp count_choices(_product, _user, _opts, counts) when counts == %{}, do: %{}

  defp count_choices(product, user, opts, counts) do
    product
    |> filter_query(user, opts)
    |> exclude(:order_by)
    |> select(^counts)
    |> Repo.one()
  end

  @summary_fields [
    :identifier,
    :description,
    :tags,
    :firmware_metadata,
    :firmware_validation_status,
    :firmware_auto_revert_detected,
    :update_mode,
    :updates_blocked_until,
    :consecutive_failed_updates,
    :first_update_failure_at,
    :last_update_failure_at,
    :deleted_at
  ]

  @summaries_max_page_size 100

  @doc """
  A page of the product's devices that `user` can see, each as a plain map,
  with the devices list's tab counts: what a devices list shows, in one call.

  `opts` takes:

    * `:pagination` - `%{page: page, page_size: page_size}`, page 1 and 10
      devices by default, and at most #{@summaries_max_page_size} devices to a
      page.
    * `:filters` - the devices list's filters (`DeviceFiltering`). `:state`
      picks a tab, and `:reason` one of the Needs attention tab's reasons, so
      `:reason` is dropped with any other tab. Soft-deleted devices are left
      out unless `:display_deleted` says otherwise or the advanced query names
      `deleted`.
    * `:sort` - `{direction, field}` as `filter/3` takes it, by identifier by
      default.

  Returns `{:ok, page}`, `page` a map of:

    * `:devices` - one map per device, in the sort's order, of:
      * `identifier`, `description`, `tags`, `firmware_validation_status`,
        `firmware_auto_revert_detected`, `update_mode`,
        `updates_blocked_until`, `consecutive_failed_updates`,
        `first_update_failure_at`, `last_update_failure_at` and `deleted_at`,
        as on `Device`
      * `firmware_metadata`, the fields of `FirmwareMetadata` as a map, or
        `nil`
      * `latest_connection`, a map of `status` and `last_seen_at`, or `nil`
        for a device that has never connected
      * `latest_health`, a map of `status`, `status_reasons` and
        `updated_at`, or `nil`
      * `deployment_group`, a map of `name`, `is_active` and
        `current_release`, or `nil`. `current_release` is
        `%{firmware: %{uuid: uuid, version: version}}`, or `nil`.

      The org and product aren't included: the caller named the product.
    * `:pagination` - `current_page`, `page_size`, `total_count` and
      `total_pages`, named as `Flop.Meta` names them. The total is the
      listed tab's count from `:state_counts`, not a count of its own.
    * `:state_counts` - as `state_counts/3` counts them.
    * `:query` - the advanced query as it ran, or `nil` without one. Free
      text comes back rewritten as a `search like` query
      (`AdvancedQuery.interpret/2`).

  The devices list ignores an advanced query that doesn't parse, and shows
  the error beside its search bar. A caller without one would read the whole
  product as the answer, so this returns
  `{:error, %{reason: :invalid_query, message: message, position: position}}`
  instead.

  Three queries, two for a page past the last device: the counts, the page's
  ids, and what the page shows. The first two read every device that
  matches, so they select no joins; only the last joins, for the page's
  devices alone.

  ## Called over `:erpc` by other applications in the cluster

  **This function has no callers inside nerves_hub_web, and that is
  expected. It is not unused. Do not remove it.** See "Cross-application
  contracts" in `AGENTS.md`.

  Another application lists a product's devices with it, for a user whose
  permission to view them it has already checked. Every key above is
  published: adding one is safe, and renaming or removing one breaks a caller
  this repository can't see. The test pins them.
  """
  @spec list_summaries(Product.t(), User.t(), map()) ::
          {:ok,
           %{
             devices: [map()],
             pagination: %{
               current_page: pos_integer(),
               page_size: pos_integer(),
               total_count: non_neg_integer(),
               total_pages: non_neg_integer()
             },
             state_counts: %{String.t() => non_neg_integer()},
             query: String.t() | nil
           }}
          | {:error, %{reason: :invalid_query, message: String.t(), position: non_neg_integer()}}
  def list_summaries(%Product{} = product, %User{} = user, opts) do
    filters = Map.get(opts, :filters) || %{}

    with {:ok, advanced_query} <- interpret_advanced_query(filters[:advanced_query], product.id) do
      {tab, tab_filters} = listed_tab(filters)

      filters =
        filters
        |> Map.drop([:state, :reason])
        |> Map.put(:advanced_query, advanced_query)
        |> Map.put_new(:display_deleted, "exclude")

      matching =
        user
        |> list_query()
        |> filter_list(product.id, Map.put(opts, :filters, filters))

      counts = count_states(matching)
      total = Map.fetch!(counts, tab)
      {page, page_size} = summaries_page(opts)

      ids =
        matching
        |> DeviceFiltering.build_filters(tab_filters)
        |> limit(^page_size)
        |> offset(^((page - 1) * page_size))
        |> select([device: d], d.id)
        |> Repo.all()

      {:ok,
       %{
         devices: summaries(ids),
         pagination: %{
           current_page: page,
           page_size: page_size,
           total_count: total,
           total_pages: div(total + page_size - 1, page_size)
         },
         state_counts: counts,
         query: advanced_query
       }}
    end
  end

  # The form the advanced query runs in, which `filter_list/3` parses again:
  # free text is rewritten as a `search like` query.
  defp interpret_advanced_query(input, product_id) when is_binary(input) do
    case String.trim(input) do
      "" ->
        {:ok, nil}

      input ->
        case AdvancedQuery.interpret(input, product_id) do
          {:ok, canonical, _ast} -> {:ok, canonical}
          {:error, message, position} -> {:error, %{reason: :invalid_query, message: message, position: position}}
        end
    end
  end

  defp interpret_advanced_query(_input, _product_id), do: {:ok, nil}

  # The tab or reason the page lists, as its key in the state counts and as
  # the filter that lists it. Every reason is part of Needs attention, so a
  # reason filter alone lists the same devices as the tab and the reason.
  # Anything the devices list doesn't have a tab or reason for lists every
  # device, as `DeviceFiltering` ignores it there too.
  defp listed_tab(filters) do
    state = if filters[:state] in DeviceFiltering.states(), do: filters[:state]
    reason = if state in [nil, "attention"] and filters[:reason] in DeviceFiltering.reasons(), do: filters[:reason]

    cond do
      reason -> {reason, %{reason: reason}}
      state -> {state, %{state: state}}
      true -> {"all", %{}}
    end
  end

  defp summaries_page(opts) do
    pagination = Map.get(opts, :pagination) || %{}
    page = positive_integer(pagination[:page], 1)
    page_size = pagination[:page_size] |> positive_integer(10) |> min(@summaries_max_page_size)
    {page, page_size}
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  # What `list_summaries/3` shows of each device, in `ids`' order, in one
  # query. A device deleted since its id was read is left out.
  defp summaries([]), do: []

  defp summaries(ids) do
    rows =
      Device
      |> where([d], d.id in ^ids)
      |> join(:left, [d], lc in assoc(d, :latest_connection))
      |> join(:left, [d], lh in assoc(d, :latest_health))
      |> join(:left, [d], dg in assoc(d, :deployment_group))
      |> join(:left, [d, _lc, _lh, dg], r in assoc(dg, :current_release))
      |> join(:left, [d, _lc, _lh, _dg, r], f in assoc(r, :firmware))
      |> select([d, lc, lh, dg, _r, f], {
        d.id,
        map(d, ^@summary_fields),
        {lc.id, map(lc, [:status, :last_seen_at])},
        {lh.id, map(lh, [:status, :status_reasons, :updated_at])},
        {dg.id, map(dg, [:name, :is_active])},
        {f.id, map(f, [:uuid, :version])}
      })
      |> Repo.all()

    by_id =
      Map.new(rows, fn {id, device, connection, health, group, firmware} ->
        [connection, health, group, firmware] = Enum.map([connection, health, group, firmware], &joined/1)
        group = group && Map.put(group, :current_release, firmware && %{firmware: firmware})

        summary =
          device
          |> Map.update!(:firmware_metadata, &(&1 && Map.from_struct(&1)))
          |> Map.merge(%{latest_connection: connection, latest_health: health, deployment_group: group})

        {id, summary}
      end)

    for id <- ids, Map.has_key?(by_id, id), do: Map.fetch!(by_id, id)
  end

  # A left join that matched nothing still selects its fields, all `nil`.
  defp joined({nil, _fields}), do: nil
  defp joined({_id, fields}), do: fields

  # The query the devices lists start from, the web UI's (`filter_query/3`),
  # the API's (`get_devices_by_org_id_and_product_id_with_pager/3`) and
  # `list_summaries/3`, so a filter or sort finds what it refers to in any of
  # them:
  #
  #   * `device`, which the alarm and metric filters correlate their
  #     subqueries to (`NervesHub.Devices.AdvancedQuery.Compiler`)
  #   * `latest_connection`, `latest_health` and `inflight_update`, left joins
  #     only filters and sorts read. Each matches at most one row per device,
  #     so Postgres drops whichever a query doesn't use.
  #
  # No list selects a join. Postgres applies OFFSET only after building every
  # row before it, so a selected join would be looked up, and sorted, for
  # every device ahead of the page. Each list loads what it shows once it has
  # its page.
  #
  # Without `visible_to`, every device is listed. That is only right for a
  # caller that already knows its actor sees all of them.
  defp list_query(visible_to) do
    Device
    |> from(as: :device)
    |> maybe_where_visible(visible_to)
    |> join(:left, [device: d], lc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:left, [device: d], lh in assoc(d, :latest_health), as: :latest_health)
    |> join(:left, [device: d], ifu in assoc(d, :inflight_update), as: :inflight_update)
  end

  defp maybe_where_visible(query, nil), do: query
  defp maybe_where_visible(query, %User{} = user), do: Visibility.where_visible(query, user)
  defp maybe_where_visible(query, %ApiKey{} = api_key), do: Visibility.where_visible(query, api_key)

  # The web UI's list also joins its user's pin on each device, as `pinned`.
  # The API's doesn't: it lists for product API keys as well as users, and
  # Postgres can't drop this join, as `pinned_devices` has no unique index.
  defp join_pinned(query, %User{id: user_id}) do
    join(query, :left, [device: d], pd in PinnedDevice,
      on: pd.device_id == d.id and pd.user_id == ^user_id,
      as: :pinned
    )
  end

  # Keeps a `list_query/1` to one product, then applies a list's sort, by
  # identifier unless `opts` says otherwise, its filters and its advanced
  # query.
  #
  # An advanced query that names `deleted` decides which soft-deleted devices
  # are listed, and the `display_deleted` filter is dropped then. Otherwise
  # `deleted = "true"` would be ANDed with `deleted_at IS NULL` and match
  # nothing.
  defp filter_list(query, product_id, opts) do
    {advanced_query, filters} = Map.pop(opts[:filters] || %{}, :advanced_query)
    names_deleted? = AdvancedQuery.references_column?(advanced_query, product_id, "deleted")
    filters = if names_deleted?, do: Map.delete(filters, :display_deleted), else: filters
    sort = opts[:sort] || {:asc, :identifier}

    query
    |> where([device: d], d.product_id == ^product_id)
    |> DeviceFiltering.sort(sort)
    |> DeviceFiltering.build_filters(filters)
    |> AdvancedQuery.apply_to_query(advanced_query, product_id)
    |> break_ties(sort)
  end

  # Postgres returns devices that tie on every sort key in whatever order it
  # finds them, and that order can change between one page's query and the
  # next, so paging by OFFSET could show a tied device twice and another
  # never. Many devices tie: every device that never connected has no
  # connection times. The id goes last, after any key a filter adds, in the
  # sort's direction, so the descending list is the ascending one reversed.
  #
  # Identifiers are unique within an org, so a sort by identifier has no ties.
  # Leaving it alone lets Postgres read a page straight off
  # `devices_product_id_identifier_index` instead of sorting.
  defp break_ties(query, {_direction, field}) when field in [:identifier, :id], do: query
  defp break_ties(query, {direction, _field}), do: order_by(query, [device: d], [{^direction, d.id}])

  def get_device_count_by_org_id(org_id) do
    q =
      from(
        d in Device,
        where: d.org_id == ^org_id,
        select: count(d)
      )

    q
    |> Repo.exclude_deleted()
    |> Repo.one!()
  end

  def get_device_count_by_product_id(product_id) do
    Device
    |> where([d], d.product_id == ^product_id)
    |> Repo.exclude_deleted()
    |> select([d], count(d))
    |> Repo.one!()
  end

  @doc """
  How many of the given products' devices `user` can see, by product. A
  product with none is left out of the map.
  """
  @spec count_by_product([pos_integer()], User.t()) :: %{pos_integer() => pos_integer()}
  def count_by_product([], _user), do: %{}

  def count_by_product(product_ids, %User{} = user) when is_list(product_ids) do
    Device
    |> where([d], d.product_id in ^product_ids)
    |> Visibility.where_visible(user)
    |> Repo.exclude_deleted()
    |> group_by([d], d.product_id)
    |> select([d], {d.product_id, count(d.id)})
    |> Repo.all()
    |> Map.new()
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
    |> Repo.exclude_deleted()
    |> Repo.fetch()
  end

  @doc """
  The device with this id, if it is in the product and not deleted.
  """
  @spec get_device_by_product(Product.t(), pos_integer()) :: {:ok, Device.t()} | {:error, :not_found}
  def get_device_by_product(%Product{id: product_id}, device_id) do
    Device
    |> where(product_id: ^product_id, id: ^device_id)
    |> Repo.exclude_deleted()
    |> Repo.fetch()
  end

  @spec get_by_identifier!(String.t()) :: Device.t()
  def get_by_identifier!(identifier) when is_binary(identifier) do
    Device
    |> join(:left, [d], o in assoc(d, :org), as: :org)
    |> where(identifier: ^identifier)
    |> preload([org: o], org: o)
    |> join_and_preload_deployment_group_and_current_release()
    |> join_and_preload([:product, :latest_connection])
    |> Repo.one!()
  end

  @spec get_by_identifier!(
          scope :: Scope.t(),
          identifier :: String.t(),
          preload_assocs :: atom() | list(atom()) | nil
        ) ::
          Device.t()
  def get_by_identifier!(scope, identifier, preload_assoc \\ [:product, :latest_connection])

  def get_by_identifier!(%Scope{} = scope, identifier, preload_assoc) when is_binary(identifier) do
    get_by_identifier_query(scope, identifier, preload_assoc)
    |> Repo.one!()
  end

  @spec get_by_identifier(
          scope :: Scope.t(),
          identifier :: String.t(),
          preload_assocs :: atom() | list(atom()) | nil
        ) ::
          {:ok, Device.t()} | {:error, :not_found}
  def get_by_identifier(%Scope{} = scope, identifier, preload_assoc \\ [:product, :latest_connection])
      when is_binary(identifier) do
    get_by_identifier_query(scope, identifier, preload_assoc)
    |> Repo.fetch()
  end

  defp get_by_identifier_query(%Scope{org: org} = scope, identifier, preload_assoc) when not is_nil(org) do
    Device
    |> Visibility.where_visible(scope)
    |> join(:left, [d], o in assoc(d, :org), as: :org)
    |> where(identifier: ^identifier)
    |> where(org_id: ^org.id)
    |> scope_to_product(scope)
    |> preload([org: o], org: o)
    |> join_and_preload_deployment_group_and_current_release()
    |> join_and_preload(preload_assoc)
  end

  defp get_by_identifier_query(%Scope{user: user} = scope, identifier, preload_assoc) when not is_nil(user) do
    Device
    |> Visibility.where_visible(user)
    |> join(:left, [d], o in assoc(d, :org), as: :org)
    |> join(:left, [d, o], u in assoc(o, :users), as: :users)
    |> where(identifier: ^identifier)
    |> where([users: u], u.id == ^user.id)
    |> where_org_not_deleted()
    |> scope_to_product(scope)
    |> preload([org: o], org: o)
    |> join_and_preload_deployment_group_and_current_release()
    |> join_and_preload(preload_assoc)
  end

  # Deleting an org leaves its memberships in place, and `org.users` only drops
  # removed members, so a lookup that reaches the device through the user's
  # membership has to rule the deleted org out itself.
  defp where_org_not_deleted(query) do
    where(query, [org: o], is_nil(o.deleted_at))
  end

  # A route carrying a :product_name segment puts the product on the scope, and
  # then the URL has to mean what it says: without this, a device was reachable
  # under any sibling product in the same org. The top-level /api/devices/:identifier
  # routes carry no product at all, so scoping only when one is present is what
  # keeps those working.
  defp scope_to_product(query, %Scope{product: nil}), do: query

  defp scope_to_product(query, %Scope{product: product}) do
    where(query, product_id: ^product.id)
  end

  @doc """
  Fetch a device by identifier, preloading its org, product, latest connection,
  deployment group and current release. Raises if the device does not exist.
  """
  def get_by_identifier_with_deployment_and_release!(identifier) do
    Device
    |> where(identifier: ^identifier)
    |> join_and_preload_deployment_group_and_current_release()
    |> preload([:org, :product, :latest_connection])
    |> Repo.one!()
  end

  defp join_and_preload_deployment_group_and_current_release(query) do
    query
    |> join(:left, [d], dp in assoc(d, :deployment_group), as: :deployment_group)
    |> join(:left, [deployment_group: dg], cr in assoc(dg, :current_release), as: :current_release)
    |> join(:left, [current_release: cr], f in assoc(cr, :firmware), as: :firmware)
    |> preload([deployment_group: dg, firmware: f, current_release: cr],
      deployment_group: {dg, current_release: {cr, firmware: f}}
    )
  end

  defp join_and_preload(query, assocs) when is_list(assocs) do
    Enum.reduce(assocs, query, fn assoc, q ->
      join_and_preload(q, assoc)
    end)
  end

  defp join_and_preload(query, nil), do: query

  defp join_and_preload(query, :deployment) do
    join_and_preload_deployment_group_and_current_release(query)
  end

  defp join_and_preload(query, :device_certificates) do
    query
    |> join(:left, [d], dc in assoc(d, :device_certificates), as: :device_certificates)
    |> preload([d, device_certificates: dc], device_certificates: dc)
  end

  defp join_and_preload(query, :network_identities) do
    query
    |> join(:left, [d], ei in assoc(d, :network_identities), as: :network_identities)
    |> preload([network_identities: ei], network_identities: ei)
  end

  defp join_and_preload(query, :latest_connection) do
    query
    |> join(:left, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
    |> preload([latest_connection: lc], latest_connection: lc)
  end

  defp join_and_preload(query, :latest_health) do
    query
    |> join(:left, [d], dh in assoc(d, :latest_health), as: :latest_health)
    |> preload([latest_health: lh], latest_health: lh)
  end

  defp join_and_preload(query, :product) do
    query
    |> join(:left, [d], p in assoc(d, :product), as: :product)
    |> preload([product: p], product: p)
  end

  @spec get_shared_secret_auth(String.t()) ::
          {:ok, SharedSecretAuth.t()} | {:error, :not_found}
  def get_shared_secret_auth(key) do
    SharedSecretAuth
    |> join(:inner, [ssa], d in assoc(ssa, :device))
    |> join(:inner, [ssa, d], p in assoc(d, :product))
    |> where([ssa], ssa.key == ^key)
    |> where([ssa], is_nil(ssa.deactivated_at))
    |> where([_, d], is_nil(d.deleted_at))
    |> preload([ssa, d, p], [:product_shared_secret_auth, device: {d, product: p}])
    |> Repo.fetch()
  end

  @doc """
  Creates a shared secret for a device, without auditing it.

  Code acting on a user's behalf uses `issue_shared_secret_auth/2`, which
  records who created the secret and audits it.
  """
  @spec create_shared_secret_auth(Device.t()) ::
          {:ok, SharedSecretAuth.t()} | {:error, Changeset.t()}
  @spec create_shared_secret_auth(Device.t(), map()) ::
          {:ok, SharedSecretAuth.t()} | {:error, Changeset.t()}
  def create_shared_secret_auth(device, attrs \\ %{}) do
    device
    |> SharedSecretAuth.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists every shared secret a device has been given, deactivated ones included,
  oldest first.

  The secrets themselves are left out, as `nil`. A secret is only returned when
  it is created, and listing them shouldn't load them into whatever holds the
  list, such as a LiveView.
  """
  @spec list_shared_secret_auths(Device.t()) :: [SharedSecretAuth.t()]
  def list_shared_secret_auths(%Device{id: device_id}) do
    SharedSecretAuth
    |> where([ssa], ssa.device_id == ^device_id)
    |> order_by([ssa], asc: ssa.id)
    |> select([ssa], struct(ssa, ^(SharedSecretAuth.__schema__(:fields) -- [:secret])))
    |> preload([:created_by, :deactivated_by])
    |> Repo.all()
  end

  @last_used_interval_seconds 15 * 60

  @doc """
  Records that a device has just connected with this shared secret.

  A device connects on every reconnect, and a whole fleet can reconnect at once
  after a deploy, so this skips the write when the key was marked in the last
  15 minutes, judged by the `last_used` already loaded. It also leaves
  `updated_at` alone, which marks changes to the key rather than its use.
  """
  @spec mark_last_used(SharedSecretAuth.t()) :: :ok
  def mark_last_used(%SharedSecretAuth{id: id, last_used: last_used}) do
    now = DateTime.utc_now(:second)
    cutoff = DateTime.add(now, -@last_used_interval_seconds, :second)

    if is_nil(last_used) or DateTime.before?(last_used, cutoff) do
      _ =
        SharedSecretAuth
        |> where([ssa], ssa.id == ^id)
        |> where([ssa], is_nil(ssa.last_used) or ssa.last_used < ^cutoff)
        |> Repo.update_all(set: [last_used: now])
    end

    :ok
  end

  @doc """
  Creates a shared secret for a device on `actor`'s behalf, recording the user
  who created it (none for a product API key), and audits it.

  Returns `{:error, :shared_secrets_not_enabled}` when this platform doesn't
  accept shared secrets, since the device could never connect with one.
  """
  @spec issue_shared_secret_auth(Device.t(), AuditLogs.actor()) ::
          {:ok, SharedSecretAuth.t()} | {:error, Changeset.t() | :shared_secrets_not_enabled}
  def issue_shared_secret_auth(device, actor) do
    if DeviceLink.shared_secrets_enabled?() do
      Repo.transact(fn ->
        with {:ok, auth} <- create_shared_secret_auth(device, %{created_by_id: AuditLogs.actor_user_id(actor)}) do
          DeviceTemplates.audit_shared_secret_created(actor, device, auth)
          {:ok, auth}
        end
      end)
    else
      {:error, :shared_secrets_not_enabled}
    end
  end

  @doc """
  Deactivates one of a device's active shared secrets on `actor`'s behalf, so
  the device can no longer connect with it, recording the user who deactivated
  it (none for a product API key), and audits it.

  A single update, so the key's ownership, that it is still active, and the
  change itself can't be split by a concurrent request. Returns
  `{:error, :not_found}` when the device has no active key by that value.

  Connections authenticated with the key are then closed. The device's other
  connections, made with a certificate or another key, stay up.
  """
  @spec deactivate_shared_secret_auth(Device.t(), String.t(), AuditLogs.actor()) ::
          {:ok, SharedSecretAuth.t()} | {:error, :not_found}
  def deactivate_shared_secret_auth(%Device{id: device_id} = device, key, actor) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.transact(fn ->
      SharedSecretAuth
      |> where([ssa], ssa.device_id == ^device_id and ssa.key == ^key and is_nil(ssa.deactivated_at))
      |> select([ssa], ssa)
      |> Repo.update_all(
        set: [
          deactivated_at: now,
          deactivated_by_id: AuditLogs.actor_user_id(actor),
          updated_at: DateTime.to_naive(now)
        ]
      )
      |> case do
        {1, [auth]} ->
          DeviceTemplates.audit_shared_secret_deactivated(actor, device, auth)
          {:ok, auth}

        {0, []} ->
          {:error, :not_found}
      end
    end)
    |> case do
      {:ok, auth} ->
        DeviceEvents.shared_secret_deactivated(auth)
        {:ok, auth}

      error ->
        error
    end
  end

  @doc """
  Creates a device together with a shared secret for it on a user's behalf, in
  one transaction.

  For provisioning, where a device must never be left registered without the
  credentials it will connect with. When the secret can't be issued, as
  `issue_shared_secret_auth/2` describes, the device isn't created either.

  Takes the same options as `create_device/4`.
  """
  @spec create_device_with_shared_secret_auth(Product.t(), map(), AuditLogs.actor(), keyword()) ::
          {:ok, {Device.t(), SharedSecretAuth.t()}} | {:error, Changeset.t() | :shared_secrets_not_enabled}
  def create_device_with_shared_secret_auth(%Product{} = product, params, actor, opts \\ []) do
    Repo.transact(fn ->
      with {:ok, device} <- create_device(product, params, actor, opts),
           {:ok, auth} <- issue_shared_secret_auth(device, actor) do
        {:ok, {device, auth}}
      end
    end)
  end

  @doc """
  Creates a device together with the certificate it will connect with, on a
  user's behalf, in one transaction.

  For a certificate no CA the org registered has signed, such as a
  self-signed one, which would otherwise be refused when the device first
  connects. When the certificate can't be saved (another device has it, say),
  the device isn't created either, and the error is the certificate's
  changeset.

  Takes the same options as `create_device/4`.
  """
  @spec create_device_with_certificate(Product.t(), map(), User.t(), X509.Certificate.t(), keyword()) ::
          {:ok, Device.t()} | {:error, Changeset.t()}
  def create_device_with_certificate(%Product{} = product, params, user, otp_cert, opts \\ []) do
    Repo.transact(fn ->
      with {:ok, device} <- create_device(product, params, user, opts),
           {:ok, _certificate} <- Certificates.create_device_certificate(device, otp_cert) do
        {:ok, device}
      end
    end)
  end

  @spec get_or_create_device(Products.SharedSecretAuth.t(), String.t()) ::
          {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_device(%Products.SharedSecretAuth{} = auth, identifier) do
    with {:error, :not_found} <-
           get_active_device(product_id: auth.product_id, identifier: identifier),
         {:ok, product} <-
           Products.get_product(auth.product_id) do
      create_device(product, %{identifier: identifier})
    end
  end

  def get_device_by(filters) do
    Repo.get_by(Device, filters)
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  @doc """
  Add a device to `product`.

  `params` can set only what `Device.create_changeset/2` allows, which takes
  the org and product from `product` and starts the device with the product's
  `default_managed_updates_allowed` as its grant.
  """
  @spec create_device(Product.t(), map()) :: {:ok, Device.t()} | {:error, Changeset.t()}
  def create_device(%Product{} = product, params) do
    product
    |> Device.create_changeset(params)
    |> Repo.insert()
    |> Repo.maybe_preload(:product)
  end

  @doc """
  Add a device to `product` on `actor`'s behalf, as `create_device/2` does.

  ## Options

    * `:managed_updates_allowed` - start the device with this grant instead of
      the product's default. When it differs from the default, it is set
      through `Updates.set_managed_updates_allowed/3` in the same transaction
      as the insert, so `actor` gets the same audit entry as for changing it
      later. As with `update_device_settings/4`, it is an option rather than a
      param so that params a form posts can't set it.
  """
  @spec create_device(Product.t(), map(), AuditLogs.actor(), keyword()) ::
          {:ok, Device.t()} | {:error, Changeset.t()}
  def create_device(%Product{} = product, params, actor, opts) do
    Repo.transact(fn ->
      with {:ok, device} <- create_device(product, params) do
        set_managed_updates_allowed(device, opts[:managed_updates_allowed], actor)
      end
    end)
  end

  def set_as_provisioned!(device) do
    device
    |> Device.changeset(%{status: :provisioned, first_seen_at: DateTime.utc_now()})
    |> Repo.update!()
  end

  @doc """
  Soft delete a device, which `restore_device/1` can undo.

  The device leaves its deployment group in the same transaction, and a
  connection it has open is closed once that commits. Left in the group and
  connected, it would still be picked by the orchestrator, which cannot penalty
  box a deleted device and so would pick it again on every run. A restored device
  is matched to a deployment group again when it next connects, as any device
  without one is.
  """
  def delete_device(%Device{} = device) do
    device_certificates_query = from(dc in DeviceCertificate, where: dc.device_id == ^device.id)
    pinned_devices_query = from(p in PinnedDevice, where: p.device_id == ^device.id)

    # A device is only soft deleted, so these have to go explicitly: otherwise
    # they keep holding the (service, identifier) unique index and reprovisioning
    # the same hardware collides with the identity of the device just deleted.
    network_identities_query = from(ei in NetworkIdentity, where: ei.device_id == ^device.id)

    changeset =
      device
      |> Device.clear_deployment_group()
      |> Repo.soft_delete_changeset()

    Multi.new()
    |> Multi.delete_all(:device_certificates, device_certificates_query)
    |> Multi.delete_all(:pinned_devices, pinned_devices_query)
    |> Multi.delete_all(:network_identities, network_identities_query)
    |> Multi.update(:device, changeset)
    |> Repo.transact()
    |> case do
      {:ok, %{device: device}} ->
        DeviceEvents.deleted(device)
        {:ok, %{device | deployment_group: nil}}

      error ->
        error
    end
  end

  @doc """
  Permanently remove a device and everything hanging off it.

  The schema's associations cover alarms, certificates, connections, network
  identities and update stats. These two are not associations of `Device`, so
  nothing cascades to them, and both reference `devices` with no action of their
  own — a device with either kind of row could not be destroyed at all.
  """
  @spec destroy_device(Device.t()) :: {:ok, Device.t()} | {:error, any()}
  def destroy_device(%Device{} = device) do
    shared_secrets_query = from(ssa in SharedSecretAuth, where: ssa.device_id == ^device.id)
    inflight_checks_query = from(c in InflightDeploymentCheck, where: c.device_id == ^device.id)

    Multi.new()
    |> Multi.delete_all(:shared_secret_auths, shared_secrets_query)
    |> Multi.delete_all(:inflight_deployment_checks, inflight_checks_query)
    |> Multi.delete(:device, device)
    |> Repo.transact()
    |> case do
      {:ok, %{device: device}} -> {:ok, device}
      error -> error
    end
  end

  def clean_up_soft_deleted_devices() do
    twelve_days_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -12, :day)

    Device
    |> where([d], d.deleted_at < ^twelve_days_ago)
    |> Repo.all()
    |> Enum.each(&clean_up_soft_deleted_device/1)
  end

  # A device that cannot be removed is reported and left for the next run, so
  # it doesn't stop the devices after it from being removed.
  defp clean_up_soft_deleted_device(device) do
    Repo.transact(fn ->
      case destroy_device(device) do
        {:ok, device} ->
          _ = ProductNotifications.create_soft_deleted_device_removed!(device)
          {:ok, device}

        error ->
          {:error, error}
      end
    end)
    |> case do
      {:ok, device} ->
        {:ok, device}

      {:error, error} ->
        _ =
          Sentry.capture_message("Error removing soft-deleted device",
            extra: %{error: inspect(error)},
            tags: soft_deleted_device_tags(device),
            result: :none
          )

        {:error, error}
    end
  rescue
    exception ->
      _ =
        Sentry.capture_exception(exception,
          stacktrace: __STACKTRACE__,
          tags: soft_deleted_device_tags(device),
          result: :none
        )

      {:error, exception}
  end

  defp soft_deleted_device_tags(device), do: %{device_id: device.id, product_id: device.product_id}

  @spec update_firmware_metadata(
          device :: Device.t(),
          connecting_metadata :: FirmwareMetadata.t() | nil,
          validation_status :: Device.firmware_validation_statuses(),
          auto_revert_detected? :: boolean()
        ) ::
          {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update_firmware_metadata(device, nil, validation_status, auto_revert_detected?) do
    Repo.transact(fn ->
      attrs = %{
        firmware_validation_status: validation_status,
        firmware_auto_revert_detected: auto_revert_detected?
      }

      attrs =
        case device.firmware_metadata do
          nil ->
            # Device joined without any known firmware metadata (e.g. its
            # uboot env had no `nerves_fw_uuid`). Nothing to report against,
            # so just persist the device-level values. This is unexpected,
            # so raise a product notification to surface it.
            _ = ProductNotifications.create_missing_firmware_metadata_notification!(device)
            attrs

          current_metadata ->
            firmware_metadata = Map.from_struct(current_metadata)

            DeviceFirmwares.add_or_update_reported_firmware(
              device,
              firmware_metadata,
              validation_status,
              auto_revert_detected?
            )
            |> case do
              :ok -> attrs
              {:ok, df} -> Map.put(attrs, :current_device_firmware_id, df.id)
            end
        end

      update_device(device, attrs)
    end)
  end

  def update_firmware_metadata(device, updated_metadata, validation_status, auto_revert_detected?) do
    Repo.transact(fn ->
      DeviceTemplates.audit_firmware_metadata_updated(device)

      updated_metadata =
        Map.new(updated_metadata, fn {k, v} ->
          if is_atom(k), do: {k, v}, else: {String.to_existing_atom(k), v}
        end)

      metadata =
        if is_nil(device.firmware_metadata) do
          updated_metadata
        else
          device.firmware_metadata
          |> Map.from_struct()
          |> Map.merge(updated_metadata)
        end

      with {:ok, device_firmware} <-
             DeviceFirmwares.add_reported_firmware(
               device,
               metadata,
               validation_status,
               auto_revert_detected?
             ) do
        update_device(device, %{
          firmware_metadata: metadata,
          firmware_validation_status: validation_status,
          firmware_auto_revert_detected: auto_revert_detected?,
          current_device_firmware_id: device_firmware.id
        })
      end
    end)
  end

  @spec update_device(Device.t(), map(), broadcast: boolean()) ::
          {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update_device(%Device{} = device, params, opts \\ []) do
    changeset = Device.changeset(device, params)

    case Repo.update(changeset) do
      {:ok, device} ->
        _ = maybe_broadcast_updated(device, opts)
        _ = maybe_broadcast_access_changed(changeset, opts)

        {:ok, device}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def restore_device(%Device{} = device) do
    update_device(device, %{deleted_at: nil})
  end

  @doc """
  Move a device to a different product

  If the new target product is in a different organization, the signing keys
  the device's current firmware was signed with are copied to that
  organization, recorded as created by `user`. The copy is part of the move's
  transaction, so a failed move leaves nothing behind in the target
  organization. It is best effort: a key the target organization cannot take,
  such as one whose name it already uses for a different key, is skipped and
  the move still succeeds.

  Moving a device will also trigger a deployment check to see if there
  is an update available from the new product/org for the device. It is
  up to the user to ensure the new device is configured with any new/different
  signing keys from the new org before moving otherwise the device
  might fail to update because of an unknown key.
  """
  @spec move(Device.t() | [Device.t()], Product.t(), User.t()) :: Repo.transaction()
  def move(%Device{} = device, product, user) do
    product = Repo.preload(product, :org)

    attrs = %{
      org_id: product.org_id,
      product_id: product.id,
      deployment_id: nil
    }

    # Written to the device and both products, so the device is a value of its
    # own rather than the entry's resource.
    description =
      Template.new("%{actor} moved device %{device} to %{org} : %{product}",
        device: device,
        org: product.org.name,
        product: product.name
      )

    source_product = %Product{
      id: device.product_id,
      org_id: device.org_id
    }

    Multi.new()
    # No "updated" broadcast: sent from inside the transaction, the device's
    # connection would re-read the row before the move committed. The
    # disconnect below is what tells it, and it reads the moved row on rejoin.
    |> Multi.run(:move, fn _, _ -> update_device(device, attrs, broadcast: false) end)
    |> Multi.delete_all(:pinned_devices, &unpin_unauthorized_users_query/1)
    # The device's identities on other networks name an organisation of their
    # own, and that is what those networks resolve a key to. Left behind, this
    # device would keep answering for the organisation it just left — and be
    # placed on that organisation's network by anything using them. Same
    # transaction as the move, so there is no window where the two disagree.
    |> Multi.update_all(
      :network_identities,
      from(ei in NetworkIdentity, where: ei.device_id == ^device.id),
      set: [org_id: product.org_id, updated_at: DateTime.utc_now(:second)]
    )
    # From the device as it was before the move, whose org the keys come from.
    # Committed before `DeviceEvents.moved_product/1` below disconnects the
    # device, which is sent its new org's keys when it reconnects.
    |> Multi.run(:signing_keys, fn _, _ ->
      Accounts.maybe_copy_firmware_keys(device, product.org, user)
    end)
    |> Multi.run(:audit_device, fn _, _ ->
      AuditLogs.audit(user, device, description, kind: :device_moved)
    end)
    |> Multi.run(:audit_target, fn _, _ ->
      AuditLogs.audit(user, product, description, kind: :device_moved)
    end)
    |> Multi.run(:audit_source, fn _, _ ->
      AuditLogs.audit(user, source_product, description, kind: :device_moved)
    end)
    |> Repo.transact()
    |> case do
      {:ok, %{move: device}} ->
        DeviceEvents.moved_product(device)
        :ok = AccessPubSub.broadcast_device_access_changed(device.id)
        {:ok, device}

      err ->
        err
    end
  end

  # Queries pinned devices where user is unauthorized to device's org.
  defp unpin_unauthorized_users_query(%{move: device}) do
    users_in_org =
      OrgUser
      |> where(org_id: ^device.org_id)
      |> select([:user_id])

    PinnedDevice
    |> where([p], p.device_id == ^device.id)
    |> where([p], p.user_id not in subquery(users_in_org))
  end

  @spec tag_device(Device.t() | [Device.t()], User.t(), list(String.t()) | String.t()) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def tag_device(%Device{} = device, user, tags) when is_list(tags) or is_binary(tags) do
    description = Template.new("%{actor} updated device %{resource} tags")
    params = %{tags: tags}
    update_device_with_audit(device, params, user, description, :tags_changed)
  end

  @doc """
  Returns the sorted, distinct list of tags used by all devices in a product.

  Used to power tag autocomplete suggestions when tagging devices or targeting
  deployment groups. Given a user, only the tags on devices they can see, so a
  role limited to some tags isn't shown the others.
  """
  @spec distinct_tags_for_product(Product.t(), User.t() | nil) :: [String.t()]
  def distinct_tags_for_product(%Product{} = product, user \\ nil) do
    Device
    |> maybe_where_visible(user)
    |> where([d], d.product_id == ^product.id)
    |> where([d], not is_nil(d.tags))
    |> select([d], fragment("distinct unnest(?)", d.tags))
    |> Repo.all()
    |> Enum.sort()
  end

  @spec add_tag(Device.t(), User.t(), String.t()) :: {:ok, Device.t()} | {:error, any()} | {:error, any(), any(), any()}
  def add_tag(%Device{} = device, user, tag) do
    tag = String.trim(tag)

    if tag == "" or String.contains?(tag, " ") do
      {:error, "Tags cannot be empty or contain spaces."}
    else
      if tag in (device.tags || []) do
        {:error, "Tag \"#{tag}\" already exists on this device."}
      else
        add_tags(device, user, [tag])
      end
    end
  end

  @spec remove_tag(Device.t(), User.t(), String.t()) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def remove_tag(%Device{} = device, user, tag) do
    remove_tags(device, user, [tag])
  end

  @doc """
  Add tags to a device, keeping the tags it already has.

  Tagging a fleet in bulk lands on devices with all sorts of existing tags, so a
  tag the device already carries is a no-op rather than an error, and a device
  that gains nothing is left untouched instead of writing an audit entry.

  The guard is load-bearing: `Ecto.Changeset.cast/4` resolves a `nil` before it
  reaches `NervesHub.Types.Tag`, so handing `nil` to the changeset would empty
  the device's tags rather than fail.
  """
  @spec add_tags(Device.t(), User.t(), list(String.t()) | String.t()) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def add_tags(%Device{} = device, user, tags) when is_list(tags) or is_binary(tags) do
    current_tags = device.tags || []

    case cast_tags(tags) do
      {:ok, tags} ->
        case Enum.reject(Enum.uniq(tags), &(&1 in current_tags)) do
          [] ->
            {:ok, device}

          added ->
            description =
              Template.new("%{actor} added the tags %{tags} to device %{resource}", tags: Enum.join(added, ", "))

            update_device_with_audit(device, %{tags: current_tags ++ added}, user, description, :tags_changed)
        end

      :error ->
        # Hand the unusable tags to the changeset, so callers get the error they
        # would get from any other bad update rather than a shape of their own.
        tag_device(device, user, tags)
    end
  end

  @doc """
  Remove tags from a device, leaving the rest of its tags alone.

  See `add_tags/3` for why a device that doesn't carry any of the tags is left
  untouched.
  """
  @spec remove_tags(Device.t(), User.t(), list(String.t()) | String.t()) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def remove_tags(%Device{} = device, user, tags) when is_list(tags) or is_binary(tags) do
    current_tags = device.tags || []

    case cast_tags(tags) do
      {:ok, tags} ->
        case Enum.split_with(current_tags, &(&1 in tags)) do
          {[], _remaining} ->
            {:ok, device}

          {removed, remaining} ->
            description =
              Template.new("%{actor} removed the tags %{tags} from device %{resource}", tags: Enum.join(removed, ", "))

            update_device_with_audit(device, %{tags: remaining}, user, description, :tags_changed)
        end

      :error ->
        tag_device(device, user, tags)
    end
  end

  defp cast_tags(tags) do
    case Tag.cast(tags) do
      {:ok, tags} -> {:ok, tags}
      _ -> :error
    end
  end

  @doc """
  Update a device and record who did it.

  The actor is usually a user, but a device is one too: a device that sets its
  own update mode, or that is moved off a mode its firmware cannot support, is
  the actor for that change, and the log should not imply an operator asked.

  `kind` says what sort of change it is, for the icon the device's Activity
  tab draws (see `NervesHub.AuditLogs.AuditLog.kinds/0`).
  """
  @spec update_device_with_audit(
          Device.t(),
          map(),
          AuditLogs.actor() | Device.t(),
          String.t() | Template.t(),
          AuditLog.kind()
        ) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def update_device_with_audit(device, params, actor, description, kind) do
    Multi.new()
    |> Multi.run(:update_with_audit, fn _, _ ->
      update_device(device, params, broadcast: false)
    end)
    |> Multi.run(:audit_device, fn _, _ ->
      AuditLogs.audit(actor, device, description, kind: kind)
    end)
    |> Repo.transact()
    |> case do
      {:ok, %{update_with_audit: updated}} ->
        DeviceEvents.updated(device)
        _ = if updated.tags != device.tags, do: AccessPubSub.broadcast_device_access_changed(device.id)
        {:ok, updated}

      err ->
        err
    end
  end

  @doc """
  Apply a change `user` makes to a device, and record who made it.

  `params` can set only what `Device.update_changeset/2` allows: the device's
  description, tags and first connect code.

  ## Options

    * `:managed_updates_allowed` - also allow (`true`) or forbid (`false`) the
      device putting itself into `:device_managed`. It goes through
      `Updates.set_managed_updates_allowed/3` in the same transaction, so it
      gets that function's own audit entry, and nothing is written when the
      device already has that value. It is an option rather than a param so
      that a settings form's params can't set it: the web UI keeps it behind a
      permission of its own.
    * `:update_mode` - also move the device to this update mode. It goes
      through `Updates.save_update_mode/3` in the same transaction, as the web
      UI's update mode buttons do: a move to `:automatic` clears the device's
      update attempts, and the audit entry names the mode. Nothing is written
      when the device already has that mode. Once the transaction commits, the
      deployment orchestrator is told about a device moved to `:automatic`, so
      it is considered straight away. `Device.cast_update_mode/2` turns a
      request's params into this option.
  """
  @spec update_device_settings(Device.t(), map(), AuditLogs.actor(), keyword()) ::
          {:ok, Device.t()} | {:error, Changeset.t()}
  def update_device_settings(%Device{} = device, params, actor, opts \\ []) do
    description = Template.new("%{actor} updated device %{resource}")

    Repo.transact(fn ->
      with {:ok, updated} <- device |> Device.update_changeset(params) |> Repo.update(),
           {:ok, _audit_log} <- AuditLogs.audit(actor, device, description, kind: :device_updated),
           {:ok, updated} <- set_managed_updates_allowed(updated, opts[:managed_updates_allowed], actor) do
        set_update_mode(updated, opts[:update_mode], actor)
      end
    end)
    |> case do
      {:ok, updated} ->
        _ = DeviceEvents.updated(updated)
        _ = if updated.update_mode != device.update_mode, do: Updates.update_mode_committed(updated)
        _ = if updated.tags != device.tags, do: AccessPubSub.broadcast_device_access_changed(device.id)
        {:ok, updated}

      error ->
        error
    end
  end

  # `Updates.set_managed_updates_allowed/3` and `Updates.save_update_mode/3`
  # announce the device as updated before the caller's transaction commits, so a
  # listener can read it unchanged. The announcement `update_device_settings/4`
  # makes after the commit is the one that sees every change; the device's
  # connection pushes the new grant and mode on that one. A device
  # `create_device/4` is still creating has no connection to tell.
  defp set_managed_updates_allowed(%Device{managed_updates_allowed: current} = device, allowed, user)
       when is_boolean(allowed) and allowed != current do
    case Updates.set_managed_updates_allowed(device, allowed, user) do
      {:ok, device} -> {:ok, device}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp set_managed_updates_allowed(device, _allowed, _user), do: {:ok, device}

  defp set_update_mode(%Device{update_mode: current} = device, mode, user) when not is_nil(mode) and mode != current do
    case Updates.save_update_mode(device, mode, user) do
      {:ok, device} -> {:ok, device}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp set_update_mode(device, _mode, _user), do: {:ok, device}

  @spec get_devices_by_id(Scope.t(), [non_neg_integer()]) :: [Device.t()]
  # A product API key reaches one product, so there is no membership to join
  # through; its own role still decides which of that product's devices it sees.
  def get_devices_by_id(%Scope{api_key: %ApiKey{} = api_key, product: product}, ids) when is_list(ids) do
    Device
    |> Visibility.where_visible(api_key)
    |> join(:left, [d], o in assoc(d, :org), as: :org)
    |> where([d], d.id in ^ids)
    |> where(product_id: ^product.id)
    |> where_org_not_deleted()
    |> Repo.all()
  end

  def get_devices_by_id(%Scope{user: user}, ids) when is_list(ids) do
    Device
    |> Visibility.where_visible(user)
    |> join(:left, [d], o in assoc(d, :org), as: :org)
    |> join(:left, [d, o], u in assoc(o, :users), as: :users)
    |> where([d], d.id in ^ids)
    |> where([users: u], u.id == ^user.id)
    |> where_org_not_deleted()
    |> Repo.all()
  end

  # A device's tags decide which custom roles see it, so sessions open on it
  # have to check again. Only once the change is committed, or they'd check
  # against the old tags; a caller passing `broadcast: false` is in a
  # transaction and does this itself afterwards.
  defp maybe_broadcast_access_changed(changeset, opts) do
    if Keyword.get(opts, :broadcast, true) and Ecto.Changeset.changed?(changeset, :tags) do
      AccessPubSub.broadcast_device_access_changed(changeset.data.id)
    end
  end

  defp maybe_broadcast_updated(device, opts) do
    if Keyword.get(opts, :broadcast, true) do
      DeviceEvents.updated(device)
    else
      :ok
    end
  end

  @doc """
  Get distinct device platforms based on the product
  """
  def platforms(product_id) do
    Device
    |> select([d], fragment("?->>'platform'", d.firmware_metadata))
    |> distinct(true)
    |> where([d], d.product_id == ^product_id)
    |> order_by([d], fragment("?->>'platform'", d.firmware_metadata))
    |> Repo.all()
  end

  @doc """
  Get distinct device architectures based on the product
  """
  def architectures(product_id) do
    Device
    |> select([d], fragment("?->>'architecture'", d.firmware_metadata))
    |> distinct(true)
    |> where([d], d.product_id == ^product_id)
    |> order_by([d], fragment("?->>'architecture'", d.firmware_metadata))
    |> Repo.all()
  end

  @doc """
  Get distinct firmware versions currently reported by the product's devices,
  newest first.

  This is the set of versions actually in use, which is a subset of the
  firmware uploaded to the product.
  """
  def firmware_versions(product_id) do
    # Distinct first so `semver_sort_key/1`, a regex, runs once per version
    # rather than once per device.
    versions =
      Device
      |> where([d], d.product_id == ^product_id)
      |> where([d], not is_nil(fragment("?->>'version'", d.firmware_metadata)))
      |> select([d], %{version: fragment("?->>'version'", d.firmware_metadata)})
      |> distinct(true)

    versions
    |> subquery()
    |> select([v], v.version)
    |> order_by([v], fragment(~s|semver_sort_key(?) COLLATE "C" DESC NULLS LAST|, v.version))
    |> Repo.all()
  end

  @doc """
  The tags on all of an org's devices, sorted. For choosing the tags a custom
  role is limited to.
  """
  @spec distinct_tags_for_org(Org.t()) :: [String.t()]
  def distinct_tags_for_org(%Org{id: org_id}) do
    Device
    |> where([d], d.org_id == ^org_id)
    |> Repo.exclude_deleted()
    |> select([d], fragment("unnest(?)", d.tags))
    |> distinct(true)
    |> Repo.all()
    |> Enum.sort()
  end

  @doc """
  Get distinct tags currently used across devices in the product. Given a user,
  only the tags on devices they can see.
  """
  def distinct_tags(product_id, user \\ nil) do
    Device
    |> maybe_where_visible(user)
    |> select([d], fragment("unnest(?)", d.tags))
    |> distinct(true)
    |> where([d], d.product_id == ^product_id)
    |> order_by([d], fragment("unnest(?)", d.tags))
    |> Repo.all()
  end

  @doc """
  The connecting code that applies to a device: its own, its deployment group's,
  and that of the release it is running (see
  `NervesHub.ManagedDeployments.join_running_release/1`), with where the
  release's code runs relative to the group's.
  """
  @spec fetch_connecting_code(pos_integer()) :: %{
          device: String.t() | nil,
          deployment_group: String.t() | nil,
          release: String.t() | nil,
          release_mode: DeploymentRelease.connecting_code_mode() | nil
        }
  def fetch_connecting_code(device_id) do
    Device
    |> from(as: :device)
    |> join(:left, [device: d], dg in assoc(d, :deployment_group), as: :deployment_group)
    |> ManagedDeployments.join_running_release()
    |> where([device: d], d.id == ^device_id)
    |> select([device: d, deployment_group: dg, running_release: rr], %{
      device: d.connecting_code,
      deployment_group: dg.connecting_code,
      release: rr.connecting_code,
      release_mode: rr.connecting_code_mode
    })
    |> Repo.one!()
  end

  @doc """
  How many of a product's devices have each extension on in their own setting,
  out of how many devices it has.

  A device's own setting only matters while the product allows the extension
  too, so this is what turning the extension on for the product would reach. A
  device with no value for an extension has the default, which is on.

      %{total: 1240, on: %{"geo" => 1228, "health" => 1240, ...}}
  """
  @spec extension_counts(Product.t()) :: %{total: non_neg_integer(), on: %{String.t() => non_neg_integer()}}
  def extension_counts(%Product{} = product) do
    keys = Enum.map(Extensions.list(), &to_string/1)

    on =
      Device
      |> where([d], d.product_id == ^product.id)
      |> Repo.exclude_deleted()
      |> join(:inner, [d], k in fragment("SELECT unnest(?::text[]) AS key", ^keys), on: true)
      |> group_by([_d, k], k.key)
      |> select([d, k], {k.key, filter(count(d.id), fragment("coalesce((?->>?)::boolean, true)", d.extensions, k.key))})
      |> Repo.all()
      |> Map.new()

    %{total: get_device_count_by_product_id(product.id), on: Map.merge(Map.new(keys, &{&1, 0}), on)}
  end

  @doc """
  How many of a product's devices may choose their own update mode.
  """
  @spec managed_updates_allowed_count(Product.t()) :: non_neg_integer()
  def managed_updates_allowed_count(%Product{} = product) do
    Device
    |> where([d], d.product_id == ^product.id and d.managed_updates_allowed)
    |> Repo.exclude_deleted()
    |> select([d], count(d.id))
    |> Repo.one!()
  end

  def enable_extension_setting(%Device{} = device, extension_string) do
    set_extension_setting(device, extension_string, true)
  end

  def disable_extension_setting(%Device{} = device, extension_string) do
    set_extension_setting(device, extension_string, false)
  end

  defp set_extension_setting(%Device{} = device, extension_string, enabled?) do
    device = get_device(device.id)
    event = if enabled?, do: "attach", else: "detach"

    Device.changeset(device, %{"extensions" => %{extension_string => enabled?}})
    |> Repo.update()
    |> tap(fn
      {:ok, _} ->
        Extensions.broadcast_extension_event(device, event, extension_string)

      _ ->
        :nope
    end)
  end

  @doc """
  Get firmware or delta.
  """

  @spec soft_deleted_devices_exist_for_product?(non_neg_integer()) :: boolean()
  def soft_deleted_devices_exist_for_product?(product_id) do
    from(d in Device,
      where: d.product_id == ^product_id,
      where: not is_nil(d.deleted_at)
    )
    |> Repo.exists?()
  end

  @doc """
  The ids of the devices in these products whose connection is open.
  """
  @spec connected_device_ids([pos_integer()]) :: [pos_integer()]
  def connected_device_ids(product_ids) do
    Device
    |> join(:inner, [d], lc in assoc(d, :latest_connection))
    |> where([d], d.product_id in ^product_ids)
    |> where([_, lc], lc.status == :connected)
    |> select([d], d.id)
    |> Repo.all()
  end

  def total_count(product) do
    Device
    |> where(product_id: ^product.id)
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end
end
