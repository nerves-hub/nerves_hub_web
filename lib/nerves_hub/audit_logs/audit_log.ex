defmodule NervesHub.AuditLogs.AuditLog do
  use Ecto.Schema

  import Ecto.Changeset
  import EctoEnum

  alias NervesHub.Accounts.Org
  alias NervesHub.Types.Resource

  @primary_key {:id, :binary_id, autogenerate: true}
  @required_params [
    :action,
    :actor_id,
    :actor_type,
    :description,
    :params,
    :resource_id,
    :resource_type,
    :org_id
  ]
  @optional_params [:reference_id]

  defenum(Action, :action, [:create, :update, :delete])

  schema "audit_logs" do
    belongs_to(:org, Org, where: [deleted_at: nil])

    field(:action, Action)
    field(:actor_id, :id)
    field(:actor_type, Resource)
    field(:description, :string)
    field(:params, :map)
    field(:resource_id, :id)
    field(:resource_type, Resource)
    field(:reference_id, :string)

    timestamps(type: :naive_datetime_usec, updated_at: false)
  end

  def build(%actor_type{} = actor, %resource_type{} = resource, action, description, params) do
    %__MODULE__{
      action: action,
      actor_id: actor.id,
      actor_type: actor_type,
      description: description,
      resource_id: resource.id,
      resource_type: resource_type,
      org_id: resource.org_id,
      params: params
    }
  end

  def build(
        %actor_type{} = actor,
        %resource_type{} = resource,
        action,
        description,
        reference_id,
        params
      ) do
    %__MODULE__{
      action: action,
      actor_id: actor.id,
      actor_type: actor_type,
      description: description,
      resource_id: resource.id,
      resource_type: resource_type,
      org_id: resource.org_id,
      reference_id: reference_id,
      params: params
    }
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
end
