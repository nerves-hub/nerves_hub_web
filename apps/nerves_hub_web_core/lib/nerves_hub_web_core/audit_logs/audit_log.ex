defmodule NervesHubWebCore.AuditLogs.AuditLog do
  use Ecto.Schema

  import Ecto.Changeset
  import EctoEnum

  alias NervesHubWebCore.{
    Accounts.Org,
    Accounts.User,
    Deployments.Deployment,
    Devices.Device,
    Firmwares.Firmware,
    Repo,
    Types.Resource
  }

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

  @identifier_fields %{
    Device => :identifier,
    Deployment => :name,
    Firmware => :uuid,
    Org => :name,
    User => :username
  }

  defenum(Action, :action, [:create, :update, :delete])

  schema "audit_logs" do
    belongs_to(:org, Org)

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

  def build(%actor_type{} = actor, %resource_type{} = resource, action, params) do
    {description, params} = Map.pop(params, :log_description)

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
    |> create_description(actor, resource)
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

  def create_description(%__MODULE__{} = audit_log) do
    %{actor_type: atype, actor_id: aid, resource_type: rtype, resource_id: rid} = audit_log

    # If the resources don't exist anymore, just build the struct
    actor = Repo.get(atype, aid) || struct(atype, id: aid)
    resource = Repo.get(rtype, rid) || struct(rtype, id: rid)

    create_description(audit_log, actor, resource)
  end

  def create_description(%{description: description} = audit_log, _, _)
      when not is_nil(description) or not description == "" do
    # use description that was already provided
    audit_log
  end

  def create_description(%{action: action} = audit_log, actor, resource)
      when action in [:create, :delete] do
    # i.e.
    #   user bob created device howdy-1234
    #   user swanson deleted deployment nunya
    %{audit_log | description: "#{identifier_for(actor)} #{action}d #{identifier_for(resource)}"}
  end

  def create_description(
        %{params: %{send_update_message: true, from: from_str}} = audit_log,
        %Deployment{} = actor,
        %Device{} = resource
      ) do
    actor = Repo.preload(actor, :firmware)

    description =
      case from_str do
        "broadcast" ->
          "#{identifier_for(actor)} update triggered #{identifier_for(resource)} to update #{
            identifier_for(actor.firmware)
          }"

        msg ->
          "#{identifier_for(resource)} received update for #{identifier_for(actor.firmware)} via #{
            identifier_for(actor)
          } after #{msg}"
      end

    %{audit_log | description: description}
  end

  def create_description(
        %{params: %{healthy: false, reason: reason}} = audit_log,
        %Deployment{} = actor,
        %Device{} = resource
      ) do
    actor = Repo.preload(actor, :firmware)

    description =
      "#{identifier_for(resource)} marked unhealthy. #{String.capitalize(reason)} for #{
        identifier_for(actor.firmware)
      } in #{identifier_for(actor)}"

    %{audit_log | description: description}
  end

  def create_description(
        %{params: %{healthy: false, reason: reason}} = audit_log,
        %Deployment{} = actor,
        %Deployment{}
      ) do
    actor = Repo.preload(actor, :firmware)

    description =
      "#{identifier_for(actor)} marked unhealthy. #{String.capitalize(reason)} for #{
        identifier_for(actor.firmware)
      }"

    %{audit_log | description: description}
  end

  def create_description(
        %{params: %{reboot: authorized?}} = audit_log,
        %User{} = actor,
        %Device{} = resource
      ) do
    reboot_str = if authorized?, do: "triggered reboot", else: "attempted unauthorized reboot"
    description = "#{identifier_for(actor)} #{reboot_str} on #{identifier_for(resource)}"
    %{audit_log | description: description}
  end

  def create_description(
        %{changes: %{healthy: healthy?}} = audit_log,
        %User{} = actor,
        resource
      ) do
    health_str = if healthy?, do: "healthy", else: "unhealthy"
    description = "#{identifier_for(actor)} marked #{identifier_for(resource)} #{health_str}"
    %{audit_log | description: description}
  end

  def create_description(
        %{changes: %{is_active: is_active?}} = audit_log,
        %User{} = actor,
        resource
      ) do
    active_str = if is_active?, do: "active", else: "inactive"
    description = "#{identifier_for(actor)} marked #{identifier_for(resource)} #{active_str}"
    %{audit_log | description: description}
  end

  def create_description(%{changes: changes} = audit_log, %User{} = actor, resource)
      when map_size(changes) == 0 do
    description =
      "#{identifier_for(actor)} submitted update without changes for #{identifier_for(resource)}"

    %{audit_log | description: description}
  end

  def create_description(%{changes: changes} = audit_log, %User{} = actor, resource) do
    changed_fields =
      Map.keys(changes)
      |> case do
        [key] -> "#{to_string(key)} field"
        [key1, key2] -> "#{key1} and #{key2} fields"
        [last_key | rem] -> Enum.join(rem, ", ") <> ", and #{last_key} fields"
      end

    # i.e.
    #   user Ron changed tags field on device 1234
    #   user Sam changed tags and description fields on device 1234
    #   user Julie changed tags, description, and version fields on deployment For Cool Kids
    description =
      "#{identifier_for(actor)} changed #{changed_fields} on #{identifier_for(resource)}"

    %{audit_log | description: description}
  end

  def create_description(audit_log, actor, resource) do
    desc =
      "#{identifier_for(actor)} performed unknown #{audit_log.action} on #{
        identifier_for(resource)
      }"

    %{audit_log | description: desc}
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

  defp identifier_for(%type{} = resource) do
    simple_type =
      to_string(type)
      |> String.downcase()
      |> String.split(".")
      |> Enum.at(-1)

    # default to DB id field if target identifier is nil
    identifier = Map.get(resource, @identifier_fields[type]) || resource.id

    # i.e.
    #   user ron.swanson
    #   deployment Awesome Deployment
    "#{simple_type} #{identifier}"
  end
end
