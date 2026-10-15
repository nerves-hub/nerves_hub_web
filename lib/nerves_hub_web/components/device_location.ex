defmodule NervesHubWeb.Components.DeviceLocation do
  use NervesHubWeb, :component

  alias NervesHub.Accounts.User.DisplayPreferences
  alias Phoenix.LiveView.JS

  attr(:location, :any)
  attr(:enable_location_editor, :boolean)
  attr(:map_style, :atom, default: nil, doc: "the user's map style, or nil to follow the theme")

  # Only rendered when a Mapbox token is configured and the Geo extension is
  # enabled for the product and device. The details tab checks that.

  # catch all to add the mapbox token
  def render(assigns) when not is_map_key(assigns, :mapbox_access_token) do
    token = Application.get_env(:nerves_hub, :mapbox_access_token)

    assigns
    |> Map.put(:mapbox_access_token, token)
    |> render()
  end

  # yay, we have a location and map key, lets display a map
  def render(%{enable_location_editor: true} = assigns) do
    ~H"""
    <div class="flex h-[450px] w-full flex-col gap-4 p-4">
      <div class="flex items-end justify-between gap-2">
        <div class="leading-6 font-medium text-base-50">Location</div>
        <div class="ml-auto text-xs font-normal text-base-400">
          Please select the devices location.
        </div>
        <.map_style_menu map_style={@map_style} />
      </div>

      <div
        id="device-location-map-with-geocoder"
        class="size-full"
        phx-hook="DeviceLocationMapWithGeocoder"
        phx-update="ignore"
        data-access-token={@mapbox_access_token}
        data-map-style={@map_style}
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
    <div class="flex h-[450px] w-full flex-col gap-4 p-4">
      <div class="flex items-end justify-between">
        <div class="leading-6 font-medium text-base-50">Location</div>
        <div class="text-xs font-normal text-base-400">The devices location is announced by the device after it connects.</div>
      </div>

      <div class="relative flex size-full flex-col items-center justify-center">
        <div class="bg-example-map-dark absolute bottom-0 left-0 z-10 size-full bg-cover bg-center blur-sm"></div>
        <div class="z-50 flex flex-col items-center gap-4">
          <div class="text-base-300">No location information found.</div>
          <div class="text-base-300">Please check if the Geo extension has been included in your firmware.</div>
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
    <div class="flex h-[450px] w-full flex-col gap-4 p-4">
      <div class="flex items-end justify-between">
        <div class="disabled:border-gray-300 disabled:bg-gray-100 disabled:checked:bg-gray-100">Location</div>
        <div class="text-xs font-normal text-base-400">The devices location is announced by the device after it connects.</div>
      </div>

      <div class="relative flex size-full flex-col items-center justify-center">
        <div class="bg-example-map-dark absolute bottom-0 left-0 z-10 size-full bg-cover bg-center blur-sm"></div>
        <div class="z-50 flex flex-col items-center gap-4">
          <div class="text-base-300">An error occurred during location resolution : {@location["error_code"]}</div>
          <div :if={@location["error_description"]} class="text-base-300">{@location["error_description"]}</div>
        </div>
      </div>
    </div>
    """
  end

  def render(%{location: %{"latitude" => latitude, "longitude" => longitude}} = assigns)
      when is_nil(latitude) or latitude == "" or is_nil(longitude) or longitude == "" do
    ~H"""
    <div class="flex h-[450px] w-full flex-col gap-4 p-4">
      <div class="flex items-end justify-between">
        <div class="leading-6 font-medium text-base-50">Location</div>
      </div>

      <div class="relative flex size-full flex-col items-center justify-center">
        <div class="bg-example-map-dark absolute bottom-0 left-0 z-10 size-full bg-cover bg-center blur-sm"></div>
        <div class="z-50 flex flex-col items-center gap-4">
          <div class="text-base-300">The location coordinates are invalid and can't be displayed.</div>
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
      map_style: assigns.map_style,
      target: assigns[:target]
    }

    source_information =
      case location["source"] do
        "manual" -> "The location was manually configured."
        _ -> "The location was determined via #{location["source"]} resolution."
      end

    assigns = Map.put(assigns, :source_information, source_information)

    ~H"""
    <div class="flex h-[450px] w-full flex-col gap-4 p-4">
      <div class="flex items-end justify-between gap-2">
        <div class="leading-6 font-medium text-base-50">Location</div>
        <div class="ml-auto text-xs font-normal text-base-400">
          {@source_information}
        </div>
        <.map_style_menu map_style={@map_style} />
        <div class="relative flex justify-end">
          <button
            class="rounded-sm border border-base-600 bg-base-800 p-0.5 hover:bg-base-700 active:bg-primary disabled:bg-base-800"
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
            <.icon name="settings" class="size-3 fill-base-400" />
          </button>

          <div
            id="location-settings-menu"
            class="absolute right-0 z-10 mt-6 w-48 origin-top-right rounded border border-base-700 bg-surface-overlay shadow-lg ring-1 ring-black/5 focus:outline-none"
            role="menu"
            style="display: none;"
            aria-orientation="vertical"
            aria-labelledby="menu-button"
            tabindex="-1"
          >
            <div role="none">
              <button phx-click="enable-location-editor" class="block w-full px-4 pt-2 pb-3 text-left text-xs text-base-300 hover:bg-base-700" role="menuitem" tabindex="-1">
                Manually update location
              </button>
              <button
                :if={@source == "manual"}
                phx-click="clear-manual-location-information"
                class="block w-full px-4 pt-2 pb-3 text-left text-xs text-base-300 hover:bg-base-700"
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
        data-center-lng={@lng}
        data-center-lat={@lat}
        data-zoom={@zoom}
        data-source={@source}
        data-map-style={@map_style}
      >
      </div>
    </div>
    """
  end

  attr(:map_style, :atom, required: true)

  # Picking a style saves it to the user's display preferences. The map hook
  # sees the new `data-map-style` when the page re-renders and restyles the map
  # in place, keeping its position and marker.
  defp map_style_menu(assigns) do
    assigns = assign(assigns, :options, [nil | DisplayPreferences.map_styles()])

    ~H"""
    <div class="relative flex justify-end">
      <button
        type="button"
        class="rounded-sm border border-base-600 bg-base-800 p-0.5 hover:bg-base-700 active:bg-primary"
        id="map-style-button"
        title="Map style"
        aria-label="Map style"
        aria-haspopup="true"
        phx-click={
          JS.toggle(
            to: "#map-style-menu",
            in: {"ease-out duration-100", "opacity-0 scale-95", "opacity-100 scale-100"},
            out: {"ease-out duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
          )
        }
        phx-click-away={
          JS.hide(
            to: "#map-style-menu",
            transition: {"ease-out duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
          )
        }
        phx-window-keydown={
          JS.hide(
            to: "#map-style-menu",
            transition: {"ease-out duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
          )
        }
        phx-key="Escape"
      >
        <span class="lucide-layers--light block size-3 text-base-400" />
      </button>

      <div
        id="map-style-menu"
        class="absolute right-0 z-10 mt-6 w-48 origin-top-right rounded border border-base-700 bg-surface-overlay py-1 shadow-lg ring-1 ring-black/5 focus:outline-none"
        role="menu"
        style="display: none;"
        aria-orientation="vertical"
        aria-labelledby="map-style-button"
        tabindex="-1"
      >
        <button
          :for={option <- @options}
          type="button"
          phx-click="set-map-style"
          phx-value-style={to_string(option)}
          class="flex w-full items-center justify-between gap-2 px-4 py-2 text-left text-xs text-base-300 hover:bg-base-700"
          role="menuitemradio"
          aria-checked={to_string(option == @map_style)}
          tabindex="-1"
        >
          {map_style_label(option)}
          <span :if={option == @map_style} class="lucide-check--light size-3.5 text-primary" />
        </button>
      </div>
    </div>
    """
  end

  defp map_style_label(nil), do: "Match theme"
  defp map_style_label(:streets), do: "Streets"
  defp map_style_label(:outdoors), do: "Outdoors"
  defp map_style_label(:light), do: "Light"
  defp map_style_label(:dark), do: "Dark"
  defp map_style_label(:satellite), do: "Satellite"
  defp map_style_label(:satellite_streets), do: "Satellite with streets"
end
