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

  def logs_for_feed(%resource_type{id: id}, opts) do
    resource_type = to_string(resource_type)

    from(al in AuditLog,
      where: [actor_type: ^resource_type, actor_id: ^id],
      or_where: [resource_type: ^resource_type, resource_id: ^id]
    )
    |> order_by(desc: :inserted_at)
    |> Repo.paginate(opts)
  end
end
