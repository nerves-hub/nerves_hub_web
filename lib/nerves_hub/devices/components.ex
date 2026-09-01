defmodule NervesHub.Devices.Components do
  @moduledoc """
  Component topologies: what a device reports itself to be made of.

  A device using the `components` extension reports assemblies of components
  and networks of peers. Each component or peer names the health metric and
  metadata keys that belong to it, and may expose actions and modes an operator
  can invoke. What an action does stays on the device; the platform only ever
  holds an identifier and a label, and asks by explicit message.

  Everything in a report is device-supplied, so it is sanitized to a fixed
  shape before storage: only known keys are kept, every value is a string (or
  list of strings), identifiers are required, and everything is bounded. Keys
  are strings throughout — device-supplied identifiers must never become atoms.
  """

  import Ecto.Query

  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices.ComponentTopology
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceMessages
  alias NervesHub.Extensions.PubSub, as: ExtensionsPubSub
  alias NervesHub.Repo

  # Bounds for a device-supplied report. Ceilings against malformed or hostile
  # payloads, not expectations — the jsonb size cap is the real limit.
  @max_groups 100
  @max_members 500
  @max_keys 100
  @max_operations 50
  @max_string_length 200

  @doc """
  Store the topology a device reported, replacing whatever it reported before.

  The raw payload is sanitized first; an unusable payload (not a map) is
  rejected. Anyone watching the device is told through
  `NervesHub.Extensions.PubSub.broadcast_report/3` with the
  `"components:updated"` event.
  """
  @spec update_topology(non_neg_integer(), map()) ::
          {:ok, ComponentTopology.t()} | {:error, Ecto.Changeset.t() | :invalid_report}
  def update_topology(device_id, raw_topology) when is_map(raw_topology) do
    topology = sanitize(raw_topology)
    now = DateTime.truncate(DateTime.utc_now(), :second)

    changeset =
      ComponentTopology.changeset(%ComponentTopology{}, %{
        device_id: device_id,
        topology: topology,
        reported_at: now
      })

    result =
      Repo.insert(changeset,
        on_conflict: [set: [topology: topology, reported_at: now, updated_at: now]],
        conflict_target: :device_id,
        returning: true
      )

    with {:ok, _component_topology} <- result do
      :ok = ExtensionsPubSub.broadcast_report(device_id, "components:updated", %{})
      result
    end
  end

  def update_topology(_device_id, _raw_topology), do: {:error, :invalid_report}

  @doc """
  The topology a device last reported, or `nil` if it never reported one.
  """
  @spec get_topology(non_neg_integer()) :: ComponentTopology.t() | nil
  def get_topology(device_id) do
    Repo.one(from(ct in ComponentTopology, where: ct.device_id == ^device_id))
  end

  @doc """
  Ask a device to run an action on one of its components.

  Audited and recorded, then sent to the device's extensions channel as an
  explicit `components:action:run` message. The returned ref correlates the
  `components:action_result` report the device answers with.
  """
  @spec request_action(User.t(), Device.t(), String.t(), String.t()) ::
          {:ok, String.t()}
          | {:error, :unknown_component | :unknown_action | term()}
  def request_action(user, device, component, action) do
    with :ok <- validate_action(device.id, component, action) do
      ref = Ecto.UUID.generate()
      payload = %{"ref" => ref, "component" => component, "action" => action}

      description =
        ~s(run action "#{action}" on component "#{component}")

      send_request(user, device, "components:action:run", payload, description, ref)
    end
  end

  @doc """
  Ask a device to set a mode on one of its components to a value.

  Audited and recorded, then sent as an explicit `components:mode:set`
  message. The returned ref correlates the `components:mode_result` report.
  """
  @spec request_mode_change(User.t(), Device.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()}
          | {:error, :unknown_component | :unknown_mode | :invalid_value | term()}
  def request_mode_change(user, device, component, mode, value) do
    with :ok <- validate_mode(device.id, component, mode, value) do
      ref = Ecto.UUID.generate()

      payload = %{"ref" => ref, "component" => component, "mode" => mode, "value" => value}

      description =
        ~s(set mode "#{mode}" to "#{value}" on component "#{component}")

      send_request(user, device, "components:mode:set", payload, description, ref)
    end
  end

  defp send_request(user, device, event, payload, description, ref) do
    result =
      Repo.transact(fn ->
        :ok = DeviceTemplates.audit_request_action(user, device, description)
        :ok = DeviceMessages.record(device, :sent, :extensions, event, payload)

        {:ok, ref}
      end)

    # Broadcast after commit: the device should never hear about a request
    # whose audit trail did not make it to disk.
    with {:ok, ref} <- result do
      :ok = ExtensionsPubSub.broadcast_to_device(device.id, event, payload)
      {:ok, ref}
    end
  end

  # A request is checked against what the device last reported, so a stale
  # page or a hand-crafted event gets an immediate error instead of a device
  # round-trip. The device still validates on its own end — this is
  # defense-in-depth, not the authority.
  defp validate_action(device_id, component, action) do
    with {:ok, member} <- find_member(device_id, component) do
      if Enum.any?(member["actions"] || [], &(&1["identifier"] == action)) do
        :ok
      else
        {:error, :unknown_action}
      end
    end
  end

  defp validate_mode(device_id, component, mode, value) do
    with {:ok, member} <- find_member(device_id, component) do
      case Enum.find(member["modes"] || [], &(&1["identifier"] == mode)) do
        nil -> {:error, :unknown_mode}
        %{"values" => values} when is_list(values) -> if(value in values, do: :ok, else: {:error, :invalid_value})
        _mode -> {:error, :invalid_value}
      end
    end
  end

  defp find_member(device_id, component) do
    case get_topology(device_id) do
      %ComponentTopology{topology: topology} ->
        members =
          Enum.flat_map(topology["assemblies"] || [], &(&1["components"] || [])) ++
            Enum.flat_map(topology["networks"] || [], &(&1["peers"] || []))

        case Enum.find(members, &(&1["identifier"] == component)) do
          nil -> {:error, :unknown_component}
          member -> {:ok, member}
        end

      nil ->
        {:error, :unknown_component}
    end
  end

  @doc """
  Reduce a device-supplied topology report to the shape that is stored.

  Only known keys survive, every kept value is a string or list of strings,
  entries without identifiers are dropped, and everything is bounded. The
  result is safe to hand to the UI: string keys only, no surprises.
  """
  @spec sanitize(map()) :: %{String.t() => [map()]}
  def sanitize(raw) when is_map(raw) do
    %{
      "assemblies" => sanitize_groups(raw["assemblies"], "components"),
      "networks" => sanitize_groups(raw["networks"], "peers")
    }
  end

  defp sanitize_groups(groups, members_key) when is_list(groups) do
    groups
    |> Enum.take(@max_groups)
    |> Enum.flat_map(fn group ->
      case sanitize_group(group, members_key) do
        nil -> []
        sanitized -> [sanitized]
      end
    end)
    |> Enum.uniq_by(& &1["identifier"])
  end

  defp sanitize_groups(_groups, _members_key), do: []

  defp sanitize_group(group, members_key) when is_map(group) do
    case string(group["identifier"]) do
      identifier when is_binary(identifier) ->
        %{
          "identifier" => identifier,
          "label" => string(group["label"]),
          "metrics" => string_list(group["metrics"], @max_keys),
          "metadata" => string_list(group["metadata"], @max_keys),
          members_key => sanitize_members(group[members_key])
        }

      _ ->
        nil
    end
  end

  defp sanitize_group(_group, _members_key), do: nil

  # Deduplicated by identifier (first wins) at every level: identifiers are
  # addressing, and ambiguous addressing helps nobody.
  defp sanitize_members(members) when is_list(members) do
    members
    |> Enum.take(@max_members)
    |> Enum.flat_map(fn member ->
      case sanitize_member(member) do
        nil -> []
        sanitized -> [sanitized]
      end
    end)
    |> Enum.uniq_by(& &1["identifier"])
  end

  defp sanitize_members(_members), do: []

  defp sanitize_member(member) when is_map(member) do
    case string(member["identifier"]) do
      identifier when is_binary(identifier) ->
        %{
          "identifier" => identifier,
          "label" => string(member["label"]),
          "metrics" => string_list(member["metrics"], @max_keys),
          "metadata" => string_list(member["metadata"], @max_keys),
          "actions" => sanitize_actions(member["actions"]),
          "modes" => sanitize_modes(member["modes"])
        }

      _ ->
        nil
    end
  end

  defp sanitize_member(_member), do: nil

  defp sanitize_actions(actions) when is_list(actions) do
    actions
    |> Enum.take(@max_operations)
    |> Enum.flat_map(fn
      %{} = action ->
        case string(action["identifier"]) do
          nil ->
            []

          identifier ->
            [
              %{
                "identifier" => identifier,
                "label" => string(action["label"]),
                "confirm" => action["confirm"] == true
              }
            ]
        end

      _ ->
        []
    end)
    |> Enum.uniq_by(& &1["identifier"])
  end

  defp sanitize_actions(_actions), do: []

  defp sanitize_modes(modes) when is_list(modes) do
    modes
    |> Enum.take(@max_operations)
    |> Enum.flat_map(fn
      %{} = mode ->
        # A mode without values would render as an empty dropdown and accept
        # anything — the link side drops them too, but the wire is not to be
        # trusted.
        with identifier when is_binary(identifier) <- string(mode["identifier"]),
             [_ | _] = values <- string_list(mode["values"], @max_operations) do
          [
            %{
              "identifier" => identifier,
              "label" => string(mode["label"]),
              "metadata_key" => string(mode["metadata_key"]) || identifier,
              "values" => values
            }
          ]
        else
          _ -> []
        end

      _ ->
        []
    end)
    |> Enum.uniq_by(& &1["identifier"])
  end

  defp sanitize_modes(_modes), do: []

  defp string(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> nil
      not String.valid?(trimmed) -> nil
      true -> String.slice(trimmed, 0, @max_string_length)
    end
  end

  defp string(_value), do: nil

  defp string_list(values, max) when is_list(values) do
    values
    |> Enum.take(max)
    |> Enum.map(&string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp string_list(_values, _max), do: []
end
