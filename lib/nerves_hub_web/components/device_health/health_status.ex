defmodule NervesHubWeb.Components.HealthStatus do
  use NervesHubWeb, :component

  attr(:device_id, :integer)
  attr(:health, :map, default: %{status: :unknown, status_reasons: nil})
  attr(:tooltip_position, :string, default: "bottom")

  def render(assigns) do
    ~H"""
    <div id={"health-tooltip-#{@device_id}"} phx-hook="ToolTip" data-placement={@tooltip_position}>
      <.icon name={icon_name(@health)} />

      <div class="tooltip-content hidden w-max absolute top-0 left-0 z-40 text-xs px-2 py-1.5 rounded border border-[#3F3F46] bg-base-900 flex">
        <%= if @health && @health.status_reasons do %>
          <div :for={{status, reasons} <- @health.status_reasons}>
            {format_health_status_reason(status, reasons)}
          </div>
        <% else %>
          <div>{no_reasons(@health)}</div>
        <% end %>
        <div class="tooltip-arrow absolute w-2 h-2 border-[#3F3F46] bg-base-900 origin-center rotate-45"></div>
      </div>
    </div>
    """
  end

  defp icon_name(nil), do: "unknown"
  defp icon_name(%{status: status}), do: to_string(status)

  def no_reasons(nil), do: "No health metrics have been received."
  def no_reasons(%{status: :healthy}), do: "Device is healthy."
  def no_reasons(%{status: :unknown}), do: "Health status is unknown."

  defp format_health_status_reason(status, reasons) do
    key_strings =
      reasons
      |> Enum.map_join(", ", fn {key, reasons} ->
        key_parts =
          key
          |> String.split("_")
          |> Enum.reject(fn p -> p == "usage" end)
          |> Enum.map(fn p -> String.capitalize(p) end)

        {key_parts, delimiter} =
          if List.last(key_parts) in ["Percent", "Percentage"] do
            {List.delete_at(key_parts, -1), "%"}
          else
            {key_parts, ""}
          end

        "#{Enum.join(key_parts, " ")}: #{reasons["value"]}#{delimiter} (threshold is #{reasons["threshold"]}#{delimiter})"
      end)

    if(!Enum.empty?(reasons)) do
      "#{String.capitalize(status)}:  #{key_strings}"
    end
  end
end
