defmodule NervesHubWeb.Components.DeviceComponents do
  @moduledoc """
  Renders a device's component topology: assemblies of components on the
  Details tab and networks of peers on the Networks tab.

  A component or peer is a box carrying the health metrics and metadata the
  topology assigns to it, plus action buttons and mode dropdowns. The topology
  is device-supplied and already sanitized (`NervesHub.Devices.Components`),
  so everything here is rendered as text; identifiers are only ever echoed
  back to the device, never interpreted.

  Actions and modes fire the `components-run-action` / `components-set-mode`
  LiveView events, which both the Details and Networks tabs route through
  `NervesHubWeb.Components.DevicePage.SharedComponentsHandlers`.
  """

  use NervesHubWeb, :component

  attr(:group, :map, required: true)
  attr(:members_key, :string, required: true, values: ["components", "peers"])
  attr(:latest_metrics, :map, default: %{})
  attr(:metadata, :map, default: %{})
  attr(:can_manage, :boolean, default: false)

  def group_box(assigns) do
    ~H"""
    <div class="bg-surface-raised border-base-700 shadow-device-details-content flex flex-col rounded border">
      <div class="flex h-14 items-center justify-between px-4">
        <div class="text-base-50 leading-6 font-medium">{title(@group)}</div>
        <span class="text-base-500 font-mono text-xs">{@group["identifier"]}</span>
      </div>

      <.value_rows entries={metric_entries(@group, @latest_metrics) ++ metadata_entries(@group, @metadata)} />

      <div class="flex flex-col gap-3 px-4 pt-2 pb-4">
        <div :if={members(@group, @members_key) == []} class="text-base-500 text-sm">
          {if @members_key == "peers", do: "No peers reported.", else: "No components reported."}
        </div>

        <%!-- The same indigo underglow as the featured metric tiles on the
        details view, pooling against a primary bottom border. --%>
        <div :for={member <- members(@group, @members_key)} class="bg-surface-muted border-b-primary border-base-700 health-neutral flex flex-col rounded border border-b">
          <div class="border-base-700 flex items-center justify-between border-b px-3 py-2">
            <span class="text-base-200 text-sm font-medium">{title(member)}</span>
            <span class="text-base-500 font-mono text-xs">{member["identifier"]}</span>
          </div>

          <.value_rows entries={metric_entries(member, @latest_metrics) ++ metadata_entries(member, @metadata)} />

          <div
            :if={member["actions"] != [] or member["modes"] != []}
            class="flex flex-wrap items-center gap-2 px-3 pt-1 pb-3"
          >
            <.button
              :for={action <- member["actions"]}
              type="button"
              style="secondary"
              phx-click="components-run-action"
              phx-value-component={member["identifier"]}
              phx-value-action={action["identifier"]}
              disabled={!@can_manage}
              aria-label={"Run #{title(action)} on #{title(member)}"}
            >
              {title(action)}
            </.button>

            <form :for={mode <- member["modes"]} id={"#{select_id(member, mode)}-form"} phx-change="components-set-mode" class="flex items-center gap-1.5">
              <input type="hidden" name="component" value={member["identifier"]} />
              <input type="hidden" name="mode" value={mode["identifier"]} />
              <label class="text-base-400 text-xs" for={select_id(member, mode)}>{title(mode)}</label>
              <select
                id={select_id(member, mode)}
                name="value"
                disabled={!@can_manage}
                class="bg-base-900 border-base-600 focus:border-base-400 text-base-300 block rounded border py-1 pr-8 pl-2 text-sm shadow-sm focus:ring-0"
              >
                <option :if={current_mode_value(mode, @metadata) == nil} value="" selected disabled>
                  select
                </option>
                <option :for={value <- mode["values"]} value={value} selected={current_mode_value(mode, @metadata) == value}>
                  {value}
                </option>
              </select>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:networks, :list, required: true)
  attr(:latest_metrics, :map, default: %{})
  attr(:metadata, :map, default: %{})
  attr(:path, :string, required: true)

  @doc """
  The Details-tab summary of the device's networks: per network its stats
  (group-level metrics and metadata) and how many peers it fronts. The peers
  themselves live on the Networks tab this links to.
  """
  def networks_summary(assigns) do
    ~H"""
    <div class="bg-surface-raised border-base-700 shadow-device-details-content flex flex-col rounded border">
      <div class="flex h-14 items-center justify-between pr-3 pl-4">
        <div class="text-base-50 leading-6 font-medium">Networks</div>
        <.link navigate={@path} class="hover:text-base-50 text-base-400 text-sm font-medium">
          View networks
        </.link>
      </div>

      <div class="flex flex-col gap-3 px-4 pb-4">
        <div :for={network <- @networks} class="bg-surface-muted border-base-700 flex flex-col rounded border">
          <div class="border-base-700 flex items-center justify-between border-b px-3 py-2">
            <span class="text-base-200 text-sm font-medium">{title(network)}</span>
            <span class="text-base-400 text-xs">{peer_count(network)}</span>
          </div>

          <.value_rows entries={metric_entries(network, @latest_metrics) ++ metadata_entries(network, @metadata)} />
        </div>
      </div>
    </div>
    """
  end

  defp peer_count(network) do
    case length(members(network, "peers")) do
      1 -> "1 peer"
      count -> "#{count} peers"
    end
  end

  attr(:entries, :list, required: true)

  defp value_rows(%{entries: []} = assigns) do
    ~H""
  end

  defp value_rows(assigns) do
    ~H"""
    <div class="flex flex-col gap-1 px-3 py-2">
      <div :for={{label, value} <- @entries} class="flex items-center justify-between gap-4">
        <span class="text-base-400 truncate text-sm">{label}</span>
        <span class="text-base-200 truncate font-mono text-sm">{value}</span>
      </div>
    </div>
    """
  end

  @doc """
  The display name of any topology entry: its label, or its identifier
  turned into a title when no label was reported.
  """
  def title(%{"label" => label}) when is_binary(label) and label != "", do: label

  def title(%{"identifier" => identifier}) when is_binary(identifier) do
    identifier
    |> String.replace(["_", "-"], " ")
    |> String.capitalize()
  end

  def title(_entry), do: ""

  @doc """
  The mode's current value, read from the health metadata entry the mode
  names. `nil` when the device hasn't reported one (or reported one outside
  the mode's value list, which the select can't represent).
  """
  def current_mode_value(mode, metadata) do
    value = Map.get(metadata || %{}, mode["metadata_key"])

    if is_binary(value) and value in mode["values"], do: value
  end

  defp members(group, members_key) do
    case group[members_key] do
      members when is_list(members) -> members
      _ -> []
    end
  end

  defp metric_entries(entry, latest_metrics) do
    for key <- entry["metrics"] || [],
        value = (latest_metrics || %{})[key],
        is_number(value) do
      {key, format_metric(value)}
    end
  end

  defp metadata_entries(entry, metadata) do
    for key <- entry["metadata"] || [],
        value = (metadata || %{})[key],
        is_binary(value) and value != "" do
      {key, value}
    end
  end

  defp format_metric(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp format_metric(value), do: to_string(value)

  defp select_id(member, mode), do: "component-mode-#{member["identifier"]}-#{mode["identifier"]}"
end
