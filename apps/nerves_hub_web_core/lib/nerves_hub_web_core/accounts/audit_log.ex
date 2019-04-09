defmodule NervesHubWebCore.Accounts.AuditLog do
  use Ecto.Schema

  import Ecto.Changeset
  import EctoEnum

  alias NervesHubWebCore.Types.Resource

  @primary_key {:id, :binary_id, autogenerate: true}
  @required_params [:action, :actor_id, :actor_type, :params, :resource_id, :resource_type]

  defenum(Action, :action, [:create, :update, :delete])

  schema "audit_logs" do
    field(:action, Action)
    field(:actor_id, :id)
    field(:actor_type, Resource)
    field(:params, :map)
    field(:resource_id, :id)
    field(:resource_type, Resource)

    timestamps(updated_at: false)
  end

  def build(%actor_type{id: actor_id}, %resource_type{id: resource_id}, action, params) do
    %__MODULE__{
      action: action,
      actor_id: actor_id,
      actor_type: actor_type,
      resource_id: resource_id,
      resource_type: resource_type,
      params: params
    }
  end

  def changeset(%__MODULE__{} = audit_log, params) do
    audit_log
    |> cast(params, @required_params)
    |> validate_required(@required_params)
  end
end
