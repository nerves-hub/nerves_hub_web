defmodule NervesHubWeb.Components.DeviceUpdateStatus do
  use NervesHubWeb, :component

  alias NervesHub.Devices

  def render(%{device: device} = assigns) do
    cond do
      Devices.device_in_penalty_box?(device) ->
        ~H"""
        <div class="relative z-20" id={"update-status-#{@device.id}"} phx-hook="ToolTip" data-placement="top">
          <svg class="size-4 stroke-amber-500 z-10" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
            <path
              d="M19 14V5C17.5 5.16667 14 5 12 3C11.4286 3.57143 10.7347 3.9932 10 4.30029M5 5V14C5 18 12 21 12 21C12 21 15.2039 19.6269 17.2766 17.5M3 3L21 21"
              stroke-width="1.2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
          <div class="tooltip-content hidden w-max absolute top-0 left-0 z-20 text-xs px-2 py-1.5 rounded border border-[#3F3F46] bg-base-900 flex">
            Updates blocked {friendly_blocked_until(@device.updates_blocked_until)}
            <div class="tooltip-arrow absolute w-2 h-2 border-[#3F3F46] bg-base-900 origin-center rotate-45"></div>
          </div>
        </div>
        """

      device.updates_enabled ->
        ~H"""
        <svg title="Updates enabled" xmlns="http://www.w3.org/2000/svg" class="size-4 stroke-emerald-500 z-10" viewBox="0 0 16 16" fill="none">
          <path
            d="M6.00016 8L7.3335 9.33333L10.0002 6M8.00016 14C8.00016 14 12.6668 12 12.6668 9.33333V3.33333C11.6668 3.44444 9.3335 3.33333 8.00016 2C6.66683 3.33333 4.3335 3.44444 3.3335 3.33333V9.33333C3.3335 12 8.00016 14 8.00016 14Z"
            stroke-width="1.2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
        """

      true ->
        ~H"""
        <div class="relative z-20" id={"update-status-#{@device.id}"} phx-hook="ToolTip" data-placement="top">
          <svg title="Updates disabled" xmlns="http://www.w3.org/2000/svg" class="size-4 stroke-red-500 z-10" viewBox="0 0 16 16" fill="none">
            <path
              d="M12.6667 9.33333V3.33333C11.6667 3.44444 9.33333 3.33333 8 2C7.61905 2.38095 7.15646 2.66213 6.66667 2.86686M3.33333 3.33333V9.33333C3.33333 12 8 14 8 14C8 14 10.1359 13.0846 11.5177 11.6667M2 2L14 14"
              stroke-width="1.2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
          <div class="tooltip-content hidden w-max absolute top-0 left-0 z-20 text-xs px-2 py-1.5 rounded border border-[#3F3F46] bg-base-900 flex">
            Updates disabled
            <div class="tooltip-arrow absolute w-2 h-2 border-[#3F3F46] bg-base-900 origin-center rotate-45"></div>
          </div>
        </div>
        """
    end
  end

  def friendly_blocked_until(blocked_until) do
    cond do
      DateTime.diff(blocked_until, DateTime.utc_now(), :second) < 60 ->
        "for less than a minute"

      DateTime.diff(blocked_until, DateTime.utc_now(), :minute) < 2 ->
        "for around a minute"

      DateTime.diff(blocked_until, DateTime.utc_now(), :minute) < 55 ->
        "for #{DateTime.diff(blocked_until, DateTime.utc_now(), :minute)} minutes"

      DateTime.diff(blocked_until, DateTime.utc_now(), :minute) < 60 ->
        "for less than an hour"

      DateTime.diff(blocked_until, DateTime.utc_now(), :minute) < 63 ->
        "for an hour"

      DateTime.diff(blocked_until, DateTime.utc_now(), :minute) < 80 ->
        "for just over an hour"

      DateTime.diff(blocked_until, DateTime.utc_now(), :minute) < 100 ->
        "for an hour and a half"

      DateTime.diff(blocked_until, DateTime.utc_now(), :minute) < 110 ->
        "for around 2 hours"

      DateTime.diff(blocked_until, DateTime.utc_now(), :hour) < 24 ->
        "for #{DateTime.diff(blocked_until, DateTime.utc_now(), :hour)} hours"

      true ->
        "until #{Calendar.strftime(blocked_until, "%B %-d, %Y %-I:%M %p %Z")}"
    end
  end
end
