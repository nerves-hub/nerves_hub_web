defmodule NervesHubWeb.Components.DeviceUpdateStatus do
  use NervesHubWeb, :component

  alias NervesHub.Devices.Updates
  alias NervesHubWeb.Components.DateTimes

  def render(%{device: device} = assigns) do
    cond do
      Updates.device_in_penalty_box?(device) ->
        ~H"""
        <.tooltip id={"update-status-#{@device.id}"} placement="top">
          <span class="lucide-shield-alert z-10 size-4 text-warning" aria-hidden="true"></span>
          <:content>
            Updates blocked {friendly_blocked_until(@device.updates_blocked_until, @time_zone)}
          </:content>
        </.tooltip>
        """

      device.update_mode != :off ->
        ~H"""
        <span class="z-10 lucide-shield-check size-4 text-success" title="Updates enabled"></span>
        """

      true ->
        ~H"""
        <.tooltip id={"update-status-#{@device.id}"} placement="top">
          <span class="z-10 lucide-shield-off size-4 text-alert" title="Updates disabled"></span>
          <:content>
            Updates disabled
          </:content>
        </.tooltip>
        """
    end
  end

  def friendly_blocked_until(blocked_until, time_zone) do
    now = DateTime.utc_now()
    seconds_diff = DateTime.diff(blocked_until, now, :second)
    minutes_diff = DateTime.diff(blocked_until, now, :minute)
    hours_diff = DateTime.diff(blocked_until, now, :hour)

    format_time_duration(seconds_diff, minutes_diff, hours_diff, blocked_until, time_zone)
  end

  defp format_time_duration(s, _m, _h, _b_u, _tz) when s < 60, do: "for less than a minute"
  defp format_time_duration(_s, m, _h, _b_u, _tz) when m < 2, do: "for around a minute"
  defp format_time_duration(_s, m, _h, _b_u, _tz) when m < 55, do: "for #{m} minutes"
  defp format_time_duration(_s, m, _h, _b_u, _tz) when m < 60, do: "for less than an hour"
  defp format_time_duration(_s, m, _h, _b_u, _tz) when m < 63, do: "for an hour"
  defp format_time_duration(_s, m, _h, _b_u, _tz) when m < 80, do: "for just over an hour"
  defp format_time_duration(_s, m, _h, _b_u, _tz) when m < 100, do: "for an hour and a half"
  defp format_time_duration(_s, m, _h, _b_u, _tz) when m < 110, do: "for around 2 hours"
  defp format_time_duration(_s, _m, h, _b_u, _tz) when h < 24, do: "for #{h} hours"

  defp format_time_duration(_s, _m, _h, blocked_until, time_zone),
    do: "until #{DateTimes.to_local_string(blocked_until, time_zone, :long_datetime)}"
end
