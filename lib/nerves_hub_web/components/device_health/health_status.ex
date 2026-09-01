defmodule NervesHubWeb.Components.HealthStatus do
  use NervesHubWeb, :component

  attr(:device_id, :integer)
  attr(:health, :map, default: %{status: :unknown, status_reasons: nil})
  attr(:tooltip_position, :string, default: "bottom")

  def render(assigns) do
    ~H"""
    <div class="relative z-20" id={"health-tooltip-#{@device_id}"} phx-hook="ToolTip" data-placement={@tooltip_position}>
      <.icon name={icon_name(@health)} />
      <div class="bg-surface-muted border-base-700 tooltip-content absolute top-0 left-0 z-20 hidden w-max rounded border px-2 py-1.5 text-xs">
        <%= if @health && @health.status_reasons do %>
          <div :for={{status, reasons} <- @health.status_reasons}>
            {format_health_status_reason(status, reasons)}
          </div>
        <% else %>
          <div>{no_reasons(@health)}</div>
        <% end %>
        <div class="bg-surface-muted border-base-700 tooltip-arrow absolute size-2 origin-center rotate-45"></div>
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

        "#{Enum.join(key_parts, " ")}: #{reasons["value"]}#{delimiter}#{window_phrase(reasons)} (threshold is #{reasons["threshold"]}#{delimiter})"
      end)

    if Enum.any?(reasons) do
      "#{String.capitalize(status)}:  #{key_strings}"
    end
  end

  # A reason judged by a health profile carries the measurement period and
  # what kind of value engaged the level (the median of reported samples, or
  # a count of events); one from the legacy instantaneous check carries
  # neither.
  defp window_phrase(%{"aggregation" => "count", "period_minutes" => minutes}) when is_integer(minutes) do
    " in #{format_period(minutes)}"
  end

  defp window_phrase(%{"period_minutes" => minutes}) when is_integer(minutes) do
    " median over #{format_period(minutes)}"
  end

  defp window_phrase(_reasons), do: ""

  defp format_period(minutes) when minutes < 60, do: "#{minutes}m"
  defp format_period(minutes) when rem(minutes, 1440) == 0, do: "#{div(minutes, 1440)}d"
  defp format_period(minutes) when rem(minutes, 60) == 0, do: "#{div(minutes, 60)}h"
  defp format_period(minutes), do: "#{div(minutes, 60)}h #{rem(minutes, 60)}m"
end
