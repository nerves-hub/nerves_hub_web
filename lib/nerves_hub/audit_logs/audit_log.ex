defmodule NervesHub.AuditLogs.AuditLog do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Types.Resource

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @required_params [
    :actor_id,
    :actor_type,
    :description,
    :resource_id,
    :resource_type,
    :org_id
  ]
  @optional_params [:reference_id]

  schema "audit_logs" do
    field(:actor_id, :id)
    field(:actor_type, Resource)
    field(:description, :string)
    field(:params, :map)
    field(:reference_id, :string)
    field(:resource_id, :id)
    field(:resource_type, Resource)

    belongs_to(:org, Org, where: [deleted_at: nil])

    timestamps(type: :naive_datetime_usec, updated_at: false)
  end

  def build(%actor_type{} = actor, %resource_type{} = resource, description) do
    %__MODULE__{
      actor_id: actor.id,
      actor_type: actor_type,
      description: description,
      org_id: resource.org_id,
      resource_id: resource.id,
      resource_type: resource_type
    }
  end

  def build(%actor_type{} = actor, %resource_type{} = resource, description, reference_id) do
    %__MODULE__{
      actor_id: actor.id,
      actor_type: actor_type,
      description: description,
      org_id: resource.org_id,
      reference_id: reference_id,
      resource_id: resource.id,
      resource_type: resource_type
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
