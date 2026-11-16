defmodule NervesHubWeb.Components.DeviceHealth.StatusBadge do
  @moduledoc """
  The badge beside a device's health readings, on the Details tab's Health
  card and the Health tab's Now card: the status of the latest evaluation and
  how many metrics engaged it, or "No recent data" once the device has gone
  quiet.
  """

  use NervesHubWeb, :component

  attr(:health, :any, required: true, doc: "the device's `latest_health`, or nil")
  attr(:stale?, :boolean, required: true, doc: "true when the device isn't connected")

  def render(assigns) do
    assigns = assign(assigns, :engaged, engaged_reasons(assigns.health))

    ~H"""
    <%= cond do %>
      <% @stale? -> %>
        <.badge dot>No recent data</.badge>
      <% @health && @health.status == :unhealthy -> %>
        <.badge tone="alert" dot>Unhealthy · {metric_count(@engaged)}</.badge>
      <% @health && @health.status == :warning -> %>
        <.badge tone="warning" dot>Warning · {metric_count(@engaged)}</.badge>
      <% @health && @health.status == :healthy -> %>
        <.badge tone="success" dot>Healthy</.badge>
      <% true -> %>
        <.badge dot>Unknown</.badge>
    <% end %>
    """
  end

  @doc """
  The engaged metrics of the latest evaluation as `{level, key, reason}`,
  alert level (`"unhealthy"`) first. Reasons come back from jsonb with string
  keys.
  """
  @spec engaged_reasons(map() | nil) :: [{String.t(), String.t(), map()}]
  def engaged_reasons(%{status_reasons: %{} = reasons}) do
    for level <- ["unhealthy", "warning"],
        {key, reason} <- Enum.sort(Map.get(reasons, level) || %{}),
        do: {level, key, reason}
  end

  def engaged_reasons(_no_health_or_reasons), do: []

  defp metric_count([_one]), do: "1 metric"
  defp metric_count(engaged), do: "#{length(engaged)} metrics"
end
