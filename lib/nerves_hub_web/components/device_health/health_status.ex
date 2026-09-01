defmodule NervesHubWeb.Components.HealthStatus do
  use NervesHubWeb, :component

  alias NervesHubWeb.Components.Utils

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

        name = Enum.join(key_parts, " ")

        # A share reason's value is how much of the window breached the
        # threshold, not a reading of the metric itself, so it gets its own
        # sentence shape.
        case reasons do
          %{"aggregation" => "share"} ->
            "#{name}: #{direction_word(reasons)} #{reasons["threshold"]}#{delimiter} for #{reasons["value"]}% of #{format_period(reasons["period_seconds"])}"

          _ ->
            "#{name}: #{reasons["value"]}#{delimiter}#{window_phrase(reasons)} (threshold is #{reasons["threshold"]}#{delimiter})"
        end
      end)

    if Enum.any?(reasons) do
      "#{String.capitalize(status)}:  #{key_strings}"
    end
  end

  # A reason judged by a health profile carries the measurement period (a
  # count reason names the window it counted over); one from the legacy
  # instantaneous check carries neither.
  defp window_phrase(%{"aggregation" => "count", "period_seconds" => seconds}) when is_integer(seconds) do
    " in #{format_period(seconds)}"
  end

  defp window_phrase(_reasons), do: ""

  # Which side of the threshold the metric breached; reasons written before
  # operators existed read as the historical at-or-over.
  defp direction_word(%{"operator" => "lte"}), do: "at or under"
  defp direction_word(_reasons), do: "at or over"

  defp format_period(seconds), do: Utils.format_period(seconds)
end
