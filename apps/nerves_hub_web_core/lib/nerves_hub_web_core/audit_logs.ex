defmodule NervesHubWebCore.AuditLogs do
  import Ecto.Query

  alias NervesHubWebCore.{Repo, AuditLogs.AuditLog}

  @default_limit 100

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

  def logs_by(%actor_type{id: id}, opts \\ []) do
    actor_type = to_string(actor_type)
    limit = opts[:limit] || @default_limit

    from(a in AuditLog, where: a.actor_type == ^actor_type, where: a.actor_id == ^id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def logs_for(%resource_type{id: id}, opts \\ []) do
    resource_type = to_string(resource_type)
    limit = opts[:limit] || @default_limit

    from(a in AuditLog, where: a.resource_type == ^resource_type, where: a.resource_id == ^id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def logs_for_feed(%resource_type{id: id}, opts \\ []) do
    resource_type = to_string(resource_type)
    limit = opts[:limit] || @default_limit

    from(al in AuditLog,
      where: [actor_type: ^resource_type, actor_id: ^id],
      or_where: [resource_type: ^resource_type, resource_id: ^id]
    )
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def from_ids(ids, opts \\ []) do
    limit = opts[:limit] || @default_limit

    from(al in AuditLog, where: al.id in ^ids)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
