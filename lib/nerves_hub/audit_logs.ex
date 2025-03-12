defmodule NervesHub.AuditLogs do
  import Ecto.Query

  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo
  alias NimbleCSV.RFC4180, as: CSV

  def audit(actor, resource, description) do
    AuditLog.build(actor, resource, description)
    |> AuditLog.changeset()
    |> Repo.insert()
  end

  def audit!(actor, resource, description) do
    AuditLog.build(actor, resource, description)
    |> AuditLog.changeset()
    |> Repo.insert!()

    :ok
  end

  def audit_with_ref!(actor, resource, description, reference_id) do
    AuditLog.build(actor, resource, description, reference_id)
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

  def logs_for_feed(resource) do
    resource
    |> query_for_feed()
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
