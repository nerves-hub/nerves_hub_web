defmodule NervesHub.AuditLogs do
  import Ecto.Query

  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.AuditLog
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
