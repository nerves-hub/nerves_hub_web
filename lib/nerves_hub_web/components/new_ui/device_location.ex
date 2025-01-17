defmodule NervesHubWeb.Components.NewUI.DeviceLocation do
  use NervesHubWeb, :component

  attr(:location, :any)
  attr(:enabled_device, :any)
  attr(:enabled_product, :any)

  # catch all to add the mapbox token
  def render(assigns) when not is_map_key(assigns, :mapbox_access_token) do
    token = Application.get_env(:nerves_hub, :mapbox_access_token)

    assigns
    |> Map.put(:mapbox_access_token, token)
    |> render()
  end

  # mapbox token is nil, maps aren't enabled
  def render(%{mapbox_access_token: nil} = assigns) do
    ~H"""
    <div class="flex flex-col w-full h-[400px] p-4 gap-4">
      <div class="flex items-end justify-between">
        <div class="text-neutral-50 font-medium leading-6">Location</div>
      </div>

      <div class="relative size-full flex flex-col items-center justify-center">
        <div class="absolute bottom-0 left-0 size-full bg-example-map-dark bg-cover bg-center blur-sm z-10"></div>
        <div class="z-50 flex flex-col items-center gap-4">
          <div class="text-zinc-300">Device maps haven't been enabled on your platform.</div>
          <div class="text-zinc-300">Please contact your platform admin.</div>
        </div>
      </div>
    </div>
    """
  end

  # disabled in product settings
  def render(%{enabled_product: false} = assigns) do
    ~H"""
    <div class="flex flex-col w-full h-[550px] p-4 gap-4">
      <div class="flex items-end justify-between">
        <div class="text-neutral-50 font-medium leading-6">Location</div>
      </div>

      <div class="relative size-full flex flex-col items-center justify-center">
        <div class="absolute bottom-0 left-0 size-full bg-example-map-dark bg-cover bg-center blur-sm z-10"></div>
        <div class="z-50 flex flex-col items-center gap-4">
          <div class="text-zinc-300">Device maps have been disabled in your product settings.</div>
          <div class="text-zinc-300">To enable this feature, please contact your product admin.</div>
        </div>
      </div>
    </div>
    """
  end

  # disabled in device settings
  def render(%{enabled_device: false} = assigns) do
    ~H"""
    <div class="flex flex-col w-full h-[550px] p-4 gap-4">
      <div class="flex items-end justify-between">
        <div class="text-neutral-50 font-medium leading-6">Location</div>
      </div>

      <div class="relative size-full flex flex-col items-center justify-center">
        <div class="absolute bottom-0 left-0 size-full bg-example-map-dark bg-cover bg-center blur-sm z-10"></div>
        <div class="z-50 flex flex-col items-center gap-4">
          <div class="text-zinc-300">Device maps have been disabled for this device.</div>
          <div class="text-zinc-300">To enable this feature, please contact your product admin.</div>
        </div>
      </div>
    </div>
    """
  end

  # location information is nil, geo location might not be enabled
  def render(%{location: nil}) do
    render(%{location: %{}})
  end

  # location information is empty, geo location might not be enabled
  def render(%{location: location} = assigns)
      when map_size(location) == 0 do
    ~H"""
    <div class="flex flex-col w-full h-[550px] p-4 gap-4">
      <div class="flex items-end justify-between">
        <div class="text-neutral-50 font-medium leading-6">Location</div>
        <div class="text-xs font-normal text-zinc-400">The devices location is announced by the device after it connects.</div>
      </div>

      <div class="relative size-full flex flex-col items-center justify-center">
        <div class="absolute bottom-0 left-0 size-full bg-example-map-dark bg-cover bg-center blur-sm z-10"></div>
        <div class="z-50 flex flex-col items-center gap-4">
          <div class="text-zinc-300">No location information found.</div>
          <div class="text-zinc-300">Please check if the Geo extension has been included in your firmware.</div>
        </div>
      </div>
    </div>
    """
  end

  # TODO: is this an API we need to document in link?
  def render(%{location: %{"error_code" => _} = location}) do
    assigns = %{location: location}

    ~H"""
    <div class="flex flex-col w-full h-[550px] p-4 gap-4">
      <div class="flex items-end justify-between">
        <div class="text-neutral-50 font-medium leading-6">Location</div>
        <div class="text-xs font-normal text-zinc-400">The devices location is announced by the device after it connects.</div>
      </div>

      <div class="relative size-full flex flex-col items-center justify-center">
        <div class="absolute bottom-0 left-0 size-full bg-example-map-dark bg-cover bg-center blur-sm z-10"></div>
        <div class="z-50 flex flex-col items-center gap-4">
          <div class="text-zinc-300">An error occurred during location resolution : <%= @location["error_code"] %></div>
          <div :if={@location["error_description"]} class="text-zinc-300"><%= @location["error_description"] %></div>
        </div>
      </div>
    </div>
    """
  end

  ###
  # TODO: add support for marker and increased zoom when source is gps
  ###

  # yay, we have a location and map key, lets display a map
  def render(%{location: location} = assigns) do
    assigns = %{
      lat: location["latitude"],
      lng: location["longitude"],
      source: location["source"],
      zoom: if(String.downcase(location["source"]) == "gps", do: 15, else: 13),
      mapbox_access_token: assigns.mapbox_access_token
    }

    ~H"""
    <div class="flex flex-col w-full h-[550px] p-4 gap-4">
      <div class="flex items-end justify-between">
        <div class="text-neutral-50 font-medium leading-6">Location</div>
        <div class="text-xs font-normal text-zinc-400">
          The location was determined via <%= @source %> resolution.
        </div>
      </div>

      <div
        id="device-location-map"
        class="size-full"
        phx-hook="DeviceLocationMap"
        phx-update="ignore"
        data-access-token={@mapbox_access_token}
        data-style="mapbox://styles/mapbox/dark-v11"
        data-center-lng={@lng}
        data-center-lat={@lat}
        data-zoom={@zoom}
        data-source={@source}
      >
      </div>
    </div>
    """
  end
end
