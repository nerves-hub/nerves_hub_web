defmodule NervesHubWebCore.AuditLogs.AuditLog do
  use Ecto.Schema

  import Ecto.Changeset
  import EctoEnum

  alias NervesHubWebCore.Repo
  alias NervesHubWebCore.Deployments.Deployment
  alias NervesHubWebCore.Accounts.Org
  alias NervesHubWebCore.Types.Resource

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
  @optional_params [:changes]

  defenum(Action, :action, [:create, :update, :delete])

  schema "audit_logs" do
    belongs_to(:org, Org, where: [deleted_at: nil])

    field(:action, Action)
    field(:actor_id, :id)
    field(:actor_type, Resource)
    field(:description, :string)
    field(:changes, :map)
    field(:params, :map)
    field(:resource_id, :id)
    field(:resource_type, Resource)

    timestamps(updated_at: false)
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
      params: format_params(actor, resource, action, params)
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

  defp format_params(
         %Deployment{} = deployment,
         _resource,
         _action,
         %{send_update_message: true} = params
       ) do
    # preload if missing, otherwise skip
    deployment = Repo.preload(deployment, :firmware)
    Map.put(params, :firmware_uuid, deployment.firmware.uuid)
  end

  defp format_params(_actor, _resource, _action, params), do: params
end
