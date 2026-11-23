defmodule NervesHub.AuditLogs do
  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.AuditLogs.Template
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Visibility
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.ApiKey
  alias NervesHub.Repo
  alias NimbleCSV.RFC4180, as: CSV

  @typedoc """
  Who did something a person could have done: a user, or a product API key
  that automation used in place of one.

  Devices and deployment groups act on their own too, and are recorded the
  same way, but they are never interchangeable with a person so they are not
  part of this.
  """
  @type actor() :: User.t() | ApiKey.t()

  @doc """
  How an actor is named at the start of an audit log description.
  """
  @spec actor_name(actor()) :: String.t()
  def actor_name(%User{name: name}), do: "User #{name}"
  def actor_name(%ApiKey{name: name}), do: "API key #{name}"

  @doc """
  The user behind `actor`, or nil when a product API key acted.

  For a column that names a user, such as who created or deleted something. A
  key leaves it empty, and the audit entry is what records the key.
  """
  @spec actor_user(actor() | nil) :: User.t() | nil
  def actor_user(%User{} = user), do: user
  def actor_user(_api_key_or_nil), do: nil

  @doc """
  The id of `actor_user/1`, for a column that holds a user's id.
  """
  @spec actor_user_id(actor() | nil) :: pos_integer() | nil
  def actor_user_id(actor) do
    case actor_user(actor) do
      %User{id: id} -> id
      nil -> nil
    end
  end

  @doc """
  Record that `actor` did something to `resource`.

  `opts` are those of `AuditLog.build/4`; pass `:kind` for anything a device's
  Activity tab shows.
  """
  def audit(actor, resource, description, opts \\ []) do
    AuditLog.build(actor, resource, description, opts)
    |> AuditLog.changeset()
    |> Repo.insert()
  end

  def audit!(actor, resource, description, opts \\ []) do
    AuditLog.build(actor, resource, description, opts)
    |> AuditLog.changeset()
    |> Repo.insert!()

    :ok
  end

  def audit_with_ref!(actor, resource, description, reference_id, opts \\ []) do
    AuditLog.build(actor, resource, description, Keyword.put(opts, :reference_id, reference_id))
    |> AuditLog.changeset()
    |> Repo.insert!()
  end

  def logs_by(%actor_type{id: id}) do
    actor_type = to_string(actor_type)

    from(a in AuditLog, where: a.actor_type == ^actor_type, where: a.actor_id == ^id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def logs_for(%resource_type{id: id}) do
    resource_type = to_string(resource_type)

    from(a in AuditLog, where: a.resource_type == ^resource_type, where: a.resource_id == ^id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  The records the template references in `entries` name, as `user` may see
  them in `org`, keyed by `{type, id}` (see `Template.reference_keys/1`).

  A reference whose record is gone, belongs to another org, or that `user`
  can't see has no key, and is shown under the name it had when the entry was
  written. That covers a device outside the tags a custom role is limited to,
  and a user who is no longer a member of `org`, whose current name the org
  has no reason to see. Devices, deployment groups, firmware and archives come
  with their product, which a link to them needs.

  One query for each type of record named, however many entries there are.
  """
  @spec load_references([AuditLog.t()], Org.t(), User.t()) :: %{{String.t(), term()} => struct()}
  def load_references(entries, %Org{} = org, %User{} = user) do
    entries
    |> Enum.flat_map(&Template.reference_keys(&1.template_values))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {type, ids} -> load_references(type, Enum.uniq(ids), org, user) end)
    |> Map.new()
  end

  defp load_references("user", ids, org, _user) do
    from(u in User,
      join: ou in OrgUser,
      on: ou.user_id == u.id and ou.org_id == ^org.id and is_nil(ou.deleted_at),
      where: u.id in ^ids and is_nil(u.deleted_at)
    )
    |> Repo.all()
    |> Enum.map(&{{"user", &1.id}, &1})
  end

  defp load_references("device", ids, org, user) do
    from(d in Device, where: d.id in ^ids and d.org_id == ^org.id and is_nil(d.deleted_at), preload: :product)
    |> Visibility.where_visible(user)
    |> Repo.all()
    |> Enum.map(&{{"device", &1.id}, &1})
  end

  defp load_references("deployment_group", ids, org, _user) do
    from(dg in DeploymentGroup, where: dg.id in ^ids and dg.org_id == ^org.id, preload: :product)
    |> Repo.all()
    |> Enum.map(&{{"deployment_group", &1.id}, &1})
  end

  # Firmware and archives are indexed by (product_id, uuid), so both are found
  # through the org's products, which gives that index its first column.
  defp load_references("firmware", uuids, org, _user) do
    from(f in Firmware,
      join: p in assoc(f, :product),
      where: p.org_id == ^org.id and f.org_id == ^org.id,
      where: f.uuid in ^uuids and is_nil(f.deleted_at),
      preload: [product: p]
    )
    |> Repo.all()
    |> Enum.map(&{{"firmware", &1.uuid}, &1})
  end

  defp load_references("archive", uuids, org, _user) do
    from(a in Archive,
      join: p in assoc(a, :product),
      where: a.uuid in ^uuids and p.org_id == ^org.id,
      preload: [product: p]
    )
    |> Repo.all()
    |> Enum.map(&{{"archive", &1.uuid}, &1})
  end

  # A type this release doesn't know, written by a newer one.
  defp load_references(_type, _ids, _org, _user), do: []

  def logs_for_feed(resource, %{page: page} = opts) when is_binary(page) do
    logs_for_feed(resource, Map.put(opts, :page, String.to_integer(page)))
  end

  def logs_for_feed(resource, opts) do
    flop = %Flop{page: opts.page, page_size: opts.page_size}

    resource
    |> query_for_feed()
    |> Flop.run(flop)
  end

  defp query_for_feed(%DeploymentGroup{id: id}) do
    resource_type = to_string(DeploymentGroup)

    from(al in AuditLog, where: [resource_type: ^resource_type, resource_id: ^id])
    |> order_by(desc: :inserted_at)
  end

  defp query_for_feed(%resource_type{id: id}) do
    resource_type = to_string(resource_type)

    union_query =
      union(
        from(al in AuditLog, where: [actor_type: ^resource_type, actor_id: ^id]),
        ^from(al in AuditLog, where: [resource_type: ^resource_type, resource_id: ^id])
      )

    # prefer union to take advantage of separate actor and resource indexes
    #
    # you cannot order_by from a union in Ecto, but a subquery works
    # https://github.com/elixir-ecto/ecto/issues/2825#issuecomment-439725204
    from(al in subquery(union_query), order_by: [desc: al.inserted_at])
  end

  @doc """
  The devices that wrote `logs`, keyed by id, for a feed that names the device
  each of its entries is about. Each is a plain map of its `:identifier` and
  whether it is `:deleted?`. A device that no longer exists is left out, so the
  feed falls back on the description.
  """
  @spec actor_devices([AuditLog.t()]) :: %{integer() => %{identifier: String.t(), deleted?: boolean()}}
  def actor_devices(logs) do
    ids = for %{actor_type: Device, actor_id: id} <- logs, uniq: true, do: id

    from(d in Device,
      where: d.id in ^ids,
      select: {d.id, %{identifier: d.identifier, deleted?: not is_nil(d.deleted_at)}}
    )
    |> Repo.all()
    |> Map.new()
  end

  def format_for_csv(audit_logs) do
    fields = AuditLog.__schema__(:fields)
    lines = for al <- audit_logs, do: Enum.map(fields, &(Map.get(al, &1) |> Jason.encode!()))

    [fields | lines]
    |> CSV.dump_to_iodata()
    |> IO.iodata_to_binary()
  end

  @spec truncate(non_neg_integer(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def truncate(org_id, days_to_keep) do
    days_ago = DateTime.shift(DateTime.utc_now(), day: -days_to_keep)

    {count, _} =
      AuditLog
      |> where([a], a.org_id == ^org_id)
      |> where([a], a.inserted_at < ^days_ago)
      |> Repo.delete_all()

    {:ok, count}
  end

  # used in some tests
  def with_description(desc) do
    where(AuditLog, [a], like(a.description, ^desc))
  end
end
