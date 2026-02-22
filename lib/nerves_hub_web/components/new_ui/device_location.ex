defmodule NervesHubWeb.Components.NewUI.DeviceLocation do
  use NervesHubWeb, :component

  alias Phoenix.LiveView.JS

  attr(:location, :any)
  attr(:enabled_device, :any)
  attr(:enabled_product, :any)
  attr(:enable_location_editor, :boolean)

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
    <div class="flex flex-col w-full h-[450px] p-4 gap-4">
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
    <div class="flex flex-col w-full h-[450px] p-4 gap-4">
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
    <div class="flex flex-col w-full h-[450px] p-4 gap-4">
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

  # yay, we have a location and map key, lets display a map
  def render(%{enable_location_editor: true} = assigns) do
    ~H"""
    <div class="flex flex-col w-full h-[450px] p-4 gap-4">
      <div class="flex items-end justify-between">
        <div class="text-neutral-50 font-medium leading-6">Location</div>
        <div class="text-xs font-normal text-zinc-400">
          Please select the devices location.
        </div>
      </div>

      <div
        id="device-location-map-with-geocoder"
        class="size-full"
        phx-hook="DeviceLocationMapWithGeocoder"
        phx-update="ignore"
        data-access-token={@mapbox_access_token}
        data-style="mapbox://styles/mapbox/dark-v11"
      >
      </div>

      <div class="flex justify-end gap-3">
        <.button phx-click="discard-location-changes">Discard changes</.button>
        <.button phx-click="save-location-changes" style="primary">Save changes</.button>
      </div>
    </div>
    """
  end

  # location information is nil or empty, geo location might not be enabled
  def render(%{location: location} = assigns) when is_nil(location) or map_size(location) == 0 do
    ~H"""
    <div class="flex flex-col w-full h-[450px] p-4 gap-4">
      <div class="flex items-end justify-between">
        <div class="text-neutral-50 font-medium leading-6">Location</div>
        <div class="text-xs font-normal text-zinc-400">The devices location is announced by the device after it connects.</div>
      </div>

      <div class="relative size-full flex flex-col items-center justify-center">
        <div class="absolute bottom-0 left-0 size-full bg-example-map-dark bg-cover bg-center blur-sm z-10"></div>
        <div class="z-50 flex flex-col items-center gap-4">
          <div class="text-zinc-300">No location information found.</div>
          <div class="text-zinc-300">Please check if the Geo extension has been included in your firmware.</div>
          <div>
            <.button phx-click="enable-location-editor">Manually set the location</.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # TODO: is this an API we need to document in link?
  def render(%{location: %{"error_code" => _} = location}) do
    assigns = %{location: location}

    ~H"""
    <div class="flex flex-col w-full h-[450px] p-4 gap-4">
      <div class="flex items-end justify-between">
        <div class="text-neutral-50 font-medium leading-6">Location</div>
        <div class="text-xs font-normal text-zinc-400">The devices location is announced by the device after it connects.</div>
      </div>

      <div class="relative size-full flex flex-col items-center justify-center">
        <div class="absolute bottom-0 left-0 size-full bg-example-map-dark bg-cover bg-center blur-sm z-10"></div>
        <div class="z-50 flex flex-col items-center gap-4">
          <div class="text-zinc-300">An error occurred during location resolution : {@location["error_code"]}</div>
          <div :if={@location["error_description"]} class="text-zinc-300">{@location["error_description"]}</div>
        </div>
      </div>
    </div>
    """
  end

  def render(%{location: %{"latitude" => latitude, "longitude" => longitude}} = assigns)
      when is_nil(latitude) or latitude == "" or is_nil(longitude) or longitude == "" do
    ~H"""
    <div class="flex flex-col w-full h-[450px] p-4 gap-4">
      <div class="flex items-end justify-between">
        <div class="text-neutral-50 font-medium leading-6">Location</div>
      </div>

      <div class="relative size-full flex flex-col items-center justify-center">
        <div class="absolute bottom-0 left-0 size-full bg-example-map-dark bg-cover bg-center blur-sm z-10"></div>
        <div class="z-50 flex flex-col items-center gap-4">
          <div class="text-zinc-300">The location coordinates are invalid and can't be displayed.</div>
        </div>
      </div>
    </div>
    """
  end

  # yay, we have a location and map key, lets display a map
  def render(%{location: location} = assigns) do
    assigns = %{
      lat: location["latitude"],
      lng: location["longitude"],
      source: location["source"],
      zoom: if(String.downcase(location["source"]) == "gps", do: 15, else: 13),
      mapbox_access_token: assigns.mapbox_access_token,
      target: assigns[:target]
    }

    source_information =
      case location["source"] do
        "manual" -> "The location was manually configured."
        _ -> "The location was determined via #{location["source"]} resolution."
      end

    assigns = Map.put(assigns, :source_information, source_information)

    ~H"""
    <div class="flex flex-col w-full h-[450px] p-4 gap-4">
      <div class="flex items-end justify-between gap-2">
        <div class="text-neutral-50 font-medium leading-6">Location</div>
        <div class="text-xs font-normal text-zinc-400 ml-auto">
          {@source_information}
        </div>
        <div class="relative flex justify-end">
          <button
            class="border rounded-sm border-zinc-600 bg-zinc-800 hover:bg-zinc-700 active:bg-indigo-500 disabled:bg-zinc-800 p-0.5"
            id="location-settings-button"
            aria-expanded="true"
            aria-haspopup="true"
            phx-click={
              JS.toggle(
                to: "#location-settings-menu",
                in: {"ease-out duration-100", "opacity-0 scale-95", "opacity-100 scale-100"},
                out: {"ease-out duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
              )
            }
            phx-click-away={
              JS.hide(
                to: "#location-settings-menu",
                transition: {"ease-out duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
              )
            }
            phx-window-keydown={
              JS.hide(
                to: "#location-settings-menu",
                transition: {"ease-out duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
              )
            }
            phx-key="Escape"
          >
            <.icon name="settings" class="size-3 fill-zinc-400" />
          </button>

          <div
            id="location-settings-menu"
            class="absolute right-0 z-10 mt-6 w-48 origin-top-right rounded bg-zinc-900 border border-zinc-700 shadow-lg ring-1 ring-black/5 focus:outline-none"
            role="menu"
            hidden="true"
            aria-orientation="vertical"
            aria-labelledby="menu-button"
            tabindex="-1"
          >
            <div role="none">
              <button phx-click="enable-location-editor" class="block w-full text-left px-4 pt-2 pb-3 text-xs text-zinc-300 hover:bg-zinc-700" role="menuitem" tabindex="-1">
                Manually update location
              </button>
              <button
                :if={@source == "manual"}
                phx-click="clear-manual-location-information"
                class="block w-full text-left px-4 pt-2 pb-3 text-xs text-zinc-300 hover:bg-zinc-700"
                role="menuitem"
                tabindex="-1"
              >
                Clear location information
              </button>
            </div>
          </div>
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
