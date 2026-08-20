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

  @description_max_length 500

  schema "audit_logs" do
    belongs_to(:org, Org, where: [deleted_at: nil])

    field(:actor_id, :id)
    field(:actor_type, Resource)
    field(:description, :string)
    field(:params, :map)
    field(:resource_id, :id)
    field(:resource_type, Resource)
    field(:reference_id, :string)

    timestamps(type: :naive_datetime_usec, updated_at: false)
  end

  def build(%actor_type{} = actor, %resource_type{} = resource, description) do
    %__MODULE__{
      actor_id: actor.id,
      actor_type: actor_type,
      description: description,
      resource_id: resource.id,
      resource_type: resource_type,
      org_id: resource.org_id
    }
  end

  def build(%actor_type{} = actor, %resource_type{} = resource, description, reference_id) do
    %__MODULE__{
      actor_id: actor.id,
      actor_type: actor_type,
      description: description,
      resource_id: resource.id,
      resource_type: resource_type,
      org_id: resource.org_id,
      reference_id: reference_id
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
    |> update_change(:description, &truncate_description/1)
    |> validate_required(@required_params)
  end

  # Descriptions are built by interpolating values which are either unbounded
  # (a device supplied failure reason) or columns which are themselves 255
  # characters wide, so cap what gets stored. Truncating rather than validating
  # is deliberate: most callers use `audit!/3`, where a validation error would
  # raise and take down the caller, which is the failure this guards against.
  defp truncate_description(description) when is_binary(description) do
    if String.length(description) > @description_max_length do
      String.slice(description, 0, @description_max_length - 1) <> "…"
    else
      description
    end
  end

  defp truncate_description(description), do: description
end
