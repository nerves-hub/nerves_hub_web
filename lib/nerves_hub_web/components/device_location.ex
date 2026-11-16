defmodule NervesHubWeb.Components.DeviceLocation do
  use NervesHubWeb, :component

  alias NervesHub.Accounts.User.DisplayPreferences
  alias Phoenix.LiveView.JS

  attr(:location, :any)
  attr(:enable_location_editor, :boolean)
  attr(:map_style, :atom, default: nil, doc: "the user's map style, or nil to follow the theme")
  attr(:editable, :boolean, default: false, doc: "whether to offer setting or clearing the location by hand")

  # Only rendered when a Mapbox token is configured and the Geo extension is
  # enabled for the product and device. The details tab checks that.

  # catch all to add the mapbox token
  def render(assigns) when not is_map_key(assigns, :mapbox_access_token) do
    token = Application.get_env(:nerves_hub, :mapbox_access_token)

    assigns
    |> Map.put(:mapbox_access_token, token)
    |> render()
  end

  def render(%{enable_location_editor: true} = assigns) do
    ~H"""
    <.location_header note="Search for the device's location, or click the map">
      <.map_style_menu map_style={@map_style} />
    </.location_header>

    <div
      id="device-location-map-with-geocoder"
      class="h-75 w-full"
      phx-hook="DeviceLocationMapWithGeocoder"
      phx-update="ignore"
      data-access-token={@mapbox_access_token}
      data-map-style={@map_style}
    >
    </div>

    <div class="flex justify-end gap-2 rounded-b-card border-t border-line-default bg-surface-muted px-4 py-2.5">
      <.button size="sm" phx-click="discard-location-changes">Discard changes</.button>
      <.button size="sm" phx-click="save-location-changes" style="primary">Save changes</.button>
    </div>
    """
  end

  # location information is nil or empty, geo location might not be enabled
  def render(%{location: location} = assigns) when is_nil(location) or map_size(location) == 0 do
    ~H"""
    <.location_header note="Announced by the device after it connects" />

    <.map_placeholder>
      <p class="text-ui font-medium text-content-strong">No location information found.</p>
      <p class="text-ui text-content-muted">Please check if the Geo extension has been included in your firmware.</p>
      <.button :if={@editable} size="sm" class="mt-1" phx-click="enable-location-editor">Manually set the location</.button>
    </.map_placeholder>
    """
  end

  # TODO: is this an API we need to document in link?
  def render(%{location: %{"error_code" => _} = location}) do
    assigns = %{location: location}

    ~H"""
    <.location_header note="Announced by the device after it connects" />

    <.map_placeholder>
      <p class="text-ui font-medium text-content-strong">An error occurred during location resolution : {@location["error_code"]}</p>
      <p :if={@location["error_description"]} class="text-ui text-content-muted">{@location["error_description"]}</p>
    </.map_placeholder>
    """
  end

  def render(%{location: %{"latitude" => latitude, "longitude" => longitude}} = assigns)
      when is_nil(latitude) or latitude == "" or is_nil(longitude) or longitude == "" do
    ~H"""
    <.location_header />

    <.map_placeholder>
      <p class="text-ui font-medium text-content-strong">The location coordinates are invalid and can't be displayed.</p>
    </.map_placeholder>
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
      target: assigns[:target],
      editable: assigns[:editable]
    }

    source_information =
      case String.downcase(to_string(location["source"])) do
        "manual" -> "Set by hand"
        "geoip" -> "Approximate, from GeoIP"
        "gps" -> "From GPS"
        _other -> "From #{location["source"]}"
      end

    assigns = Map.put(assigns, :source_information, source_information)

    ~H"""
    <.location_header note={@source_information}>
      <.map_style_menu map_style={@map_style} />
      <div :if={@editable} class="relative flex justify-end">
        <button
          class="flex size-7 cursor-pointer items-center justify-center rounded border border-line-default text-content-muted hover:bg-surface-muted hover:text-content-strong"
          id="location-settings-button"
          title="Location settings"
          aria-label="Location settings"
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
          <span class="lucide-settings size-3.5" aria-hidden="true"></span>
        </button>

        <div
          id="location-settings-menu"
          class="absolute top-8 right-0 z-10 w-48 origin-top-right rounded-md border border-line-default bg-surface-overlay py-1 shadow-overlay focus:outline-none"
          role="menu"
          style="display: none;"
          aria-orientation="vertical"
          aria-labelledby="location-settings-button"
          tabindex="-1"
        >
          <button phx-click="enable-location-editor" class="block w-full px-4 py-2 text-left text-xs text-content-body hover:bg-surface-muted" role="menuitem" tabindex="-1">
            Manually update location
          </button>
          <button
            :if={@source == "manual"}
            phx-click="clear-manual-location-information"
            class="block w-full px-4 py-2 text-left text-xs text-content-body hover:bg-surface-muted"
            role="menuitem"
            tabindex="-1"
          >
            Clear location information
          </button>
        </div>
      </div>
    </.location_header>

    <div
      id="device-location-map"
      class="h-75 w-full"
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

    <div class="flex h-10 items-center rounded-b-card border-t border-line-default px-4 font-mono text-xs text-content-muted">
      {format_coordinate(@lat, "N", "S")}, {format_coordinate(@lng, "E", "W")}
    </div>
    """
  end

  attr(:note, :string, default: nil)
  slot(:inner_block)

  defp location_header(assigns) do
    ~H"""
    <div class="flex h-12 shrink-0 items-center gap-2 px-4">
      <h2 class="text-sm/4.5 font-semibold text-content-strong">Location</h2>
      <span :if={@note} class="min-w-0 truncate text-xs text-content-faint">· {@note}</span>
      <div class="ml-auto flex items-center gap-1.5">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  slot(:inner_block, required: true)

  defp map_placeholder(assigns) do
    ~H"""
    <div class="relative flex h-75 w-full flex-col items-center justify-center overflow-hidden rounded-b-card border-t border-line-default">
      <div class="bg-example-map-dark absolute inset-0 bg-cover bg-center opacity-40 blur-sm"></div>
      <div class="relative flex flex-col items-center gap-2 px-6 text-center">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp format_coordinate(value, positive, negative) when is_number(value) do
    hemisphere = if value < 0, do: negative, else: positive

    "#{:erlang.float_to_binary(abs(value) / 1, decimals: 4)}° #{hemisphere}"
  end

  defp format_coordinate(value, _positive, _negative), do: to_string(value)

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
        class="flex size-7 cursor-pointer items-center justify-center rounded border border-line-default text-content-muted hover:bg-surface-muted hover:text-content-strong"
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
        <span class="lucide-layers size-3.5" aria-hidden="true" />
      </button>

      <div
        id="map-style-menu"
        class="absolute top-8 right-0 z-10 w-48 origin-top-right rounded-md border border-line-default bg-surface-overlay py-1 shadow-overlay focus:outline-none"
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
          class="flex w-full items-center justify-between gap-2 px-4 py-2 text-left text-xs text-content-body hover:bg-surface-muted"
          role="menuitemradio"
          aria-checked={to_string(option == @map_style)}
          tabindex="-1"
        >
          {map_style_label(option)}
          <span :if={option == @map_style} class="lucide-check--bold size-3.5 text-primary" />
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
