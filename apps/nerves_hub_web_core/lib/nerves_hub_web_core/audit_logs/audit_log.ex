defmodule NervesHubWebCore.AuditLogs.AuditLog do
  use Ecto.Schema

  import Ecto.Changeset
  import EctoEnum

  alias NervesHubWebCore.Types.Resource

  @primary_key {:id, :binary_id, autogenerate: true}
  @required_params [:action, :actor_id, :actor_type, :params, :resource_id, :resource_type]
  @optional_params [:changes]

  defenum(Action, :action, [:create, :update, :delete])

  schema "audit_logs" do
    field(:action, Action)
    field(:actor_id, :id)
    field(:actor_type, Resource)
    field(:changes, :map)
    field(:params, :map)
    field(:resource_id, :id)
    field(:resource_type, Resource)

    timestamps(updated_at: false)
  end

  def build(%actor_type{id: actor_id}, %resource_type{id: resource_id} = resource, action, params) do
    %__MODULE__{
      action: action,
      actor_id: actor_id,
      actor_type: actor_type,
      resource_id: resource_id,
      resource_type: resource_type,
      params: params
    }
    |> add_changes(resource)
  end

  def changeset(params) do
    changeset(%__MODULE__{}, params)
  end

  def changeset(audit_log, [i | _] = params) when is_tuple(i) do
    changeset(audit_log, Map.new(params))
  end

  def changeset(audit_log, %{__struct__: _} = params) do
    changeset(audit_log, Map.delete(params, :__struct__))
  end

  def changeset(%__MODULE__{} = audit_log, params) do
    audit_log
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
  end

  defp add_changes(
         %__MODULE__{action: :update, params: params, resource_type: type} = audit_log,
         resource
       ) do
    %{audit_log | changes: type.changeset(resource, params).changes}
  end

  defp add_changes(audit_log, _resource), do: audit_log
end
