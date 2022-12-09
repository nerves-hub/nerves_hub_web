defmodule NervesHubWebCore.AuditLogs do
  import Ecto.Query

  alias NervesHubWebCore.{Repo, AuditLogs.AuditLog}

  def audit(actor, resource, action, params) do
    AuditLog.build(actor, resource, action, params)
    |> AuditLog.changeset()
    |> Repo.insert()
  end

  def audit!(actor, resource, action, params) do
    AuditLog.build(actor, resource, action, params)
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

  def logs_for_feed(%resource_type{id: id}) do
    resource_type = to_string(resource_type)

    from(al in AuditLog,
      where: [actor_type: ^resource_type, actor_id: ^id],
      or_where: [resource_type: ^resource_type, resource_id: ^id]
    )
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def from_ids(ids) do
    from(al in AuditLog, where: al.id in ^ids)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def truncate(opts \\ []) do
    max_records_per_resource_per_run =
      Keyword.get(opts, :max_records_per_resource_per_run, 100_000)

    max_resources_per_run = Keyword.get(opts, :max_resources_per_run, 50)
    retain_per_resource = Keyword.get(opts, :retain_per_resource, 10_000)

    over_limit =
      from(
        a in AuditLog,
        as: :audit_log,
        group_by: [a.resource_type, a.resource_id],
        order_by: [desc: count()],
        limit: ^max_resources_per_run,
        having: count() > ^retain_per_resource,
        select: map(a, [:resource_type, :resource_id])
      )
      |> Repo.all()

    Enum.each(over_limit, fn %{resource_type: resource_type, resource_id: resource_id} ->
      to_delete =
        from(a in AuditLog,
          where: a.resource_type == ^resource_type,
          where: a.resource_id == ^resource_id,
          order_by: [asc: :inserted_at],
          offset: ^retain_per_resource,
          limit: ^max_records_per_resource_per_run,
          select: a.id
        )

      AuditLog
      |> where([a], a.id in subquery(to_delete))
      |> Repo.delete_all()
    end)
  end
end
