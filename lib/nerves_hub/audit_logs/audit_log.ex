defmodule NervesHub.AuditLogs.AuditLog do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Types.Resource

  @type t :: %__MODULE__{}

  # What happened, for the entries a device's Activity tab shows, so the web UI
  # can draw each one without reading its description. The description stays
  # the record of what happened; the kind only sorts it. Rows written before
  # kinds existed, and entries about other resources, have none.
  #
  # Ecto.Enum won't load a value it doesn't list, so a node still on an older
  # release fails to read an entry with a kind added after it. Add a kind in
  # one release and start writing it in the next.
  @kinds [
    :archive_sent,
    :deployment_group_mismatch,
    :deployment_group_set,
    :deployment_update_sent,
    :device_moved,
    :device_rebooted,
    :device_updated,
    :firmware_metadata_updated,
    :firmware_pushed,
    :firmware_updated,
    :firmware_validated,
    :identify_requested,
    :managed_updates_changed,
    :penalty_box_cleared,
    :reconnect_requested,
    :script_run,
    :shared_secret_created,
    :shared_secret_deactivated,
    :tags_changed,
    :update_attempted,
    :update_failed,
    :update_ignored,
    :update_mode_changed,
    :update_requested,
    :update_rescheduled,
    :updates_blocked,
    :updates_disabled,
    :updates_enabled
  ]

  @type kind ::
          :archive_sent
          | :deployment_group_mismatch
          | :deployment_group_set
          | :deployment_update_sent
          | :device_moved
          | :device_rebooted
          | :device_updated
          | :firmware_metadata_updated
          | :firmware_pushed
          | :firmware_updated
          | :firmware_validated
          | :identify_requested
          | :managed_updates_changed
          | :penalty_box_cleared
          | :reconnect_requested
          | :script_run
          | :shared_secret_created
          | :shared_secret_deactivated
          | :tags_changed
          | :update_attempted
          | :update_failed
          | :update_ignored
          | :update_mode_changed
          | :update_requested
          | :update_rescheduled
          | :updates_blocked
          | :updates_disabled
          | :updates_enabled

  @primary_key {:id, :binary_id, autogenerate: true}
  @required_params [
    :actor_id,
    :actor_type,
    :description,
    :resource_id,
    :resource_type,
    :org_id
  ]
  @optional_params [:kind, :reference_id]

  @description_max_length 500

  schema "audit_logs" do
    belongs_to(:org, Org, where: [deleted_at: nil])

    field(:actor_id, :id)
    field(:actor_type, Resource)
    field(:description, :string)
    field(:kind, Ecto.Enum, values: @kinds)
    field(:params, :map)
    field(:resource_id, :id)
    field(:resource_type, Resource)
    field(:reference_id, :string)

    timestamps(type: :naive_datetime_usec, updated_at: false)
  end

  @doc """
  Build an entry recording that `actor` did something to `resource`.

  ## Options

    * `:kind` - what happened, one of `kinds/0`. Set it for anything a device's
      Activity tab shows, which draws an icon for it.
    * `:reference_id` - ties together entries written for one operation.
  """
  @spec build(struct(), struct(), String.t(), keyword()) :: t()
  def build(%actor_type{} = actor, %resource_type{} = resource, description, opts \\ []) do
    %__MODULE__{
      actor_id: actor.id,
      actor_type: actor_type,
      description: description,
      kind: opts[:kind],
      resource_id: resource.id,
      resource_type: resource_type,
      org_id: org_id(resource),
      reference_id: opts[:reference_id]
    }
  end

  @doc "Every kind an entry can have."
  @spec kinds() :: [kind(), ...]
  def kinds(), do: @kinds

  # Most resources belong to an organization; an organization is its own.
  defp org_id(%Org{id: id}), do: id
  defp org_id(resource), do: resource.org_id

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
