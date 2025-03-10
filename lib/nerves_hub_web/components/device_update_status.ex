defmodule NervesHubWeb.Components.DeviceUpdateStatus do
  use NervesHubWeb, :component

  alias NervesHub.Devices

  def render(%{device: device} = assigns) do
    cond do
      Devices.device_in_penalty_box?(device) ->
        ~H"""
        <svg title="Device in the penalty box" class="size-4 stroke-amber-500" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
          <path
            d="M19 14V5C17.5 5.16667 14 5 12 3C11.4286 3.57143 10.7347 3.9932 10 4.30029M5 5V14C5 18 12 21 12 21C12 21 15.2039 19.6269 17.2766 17.5M3 3L21 21"
            stroke-width="1.2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
        """

      device.updates_enabled ->
        ~H"""
        <svg title="Updates enabled" xmlns="http://www.w3.org/2000/svg" class="size-4 stroke-emerald-500" viewBox="0 0 16 16" fill="none">
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
        <svg title="Updates disabled" xmlns="http://www.w3.org/2000/svg" class="size-4 stroke-zinc-400" viewBox="0 0 16 16" fill="none">
          <path
            d="M12.6667 9.33333V3.33333C11.6667 3.44444 9.33333 3.33333 8 2C7.61905 2.38095 7.15646 2.66213 6.66667 2.86686M3.33333 3.33333V9.33333C3.33333 12 8 14 8 14C8 14 10.1359 13.0846 11.5177 11.6667M2 2L14 14"
            stroke-width="1.2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
        """
    end
  end
end
