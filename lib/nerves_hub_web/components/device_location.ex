defmodule NervesHubWeb.Components.DeviceLocation do
  use NervesHubWeb, :component

  attr(:location, :any)

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
    <div class="display-box">
      <.location_header tooltip="The devices location is determined by looking up the request IP of the device using a GeoIP database." />

      <div>
        <span class="color-white-50">Device maps haven't been enabled on your platform.</span>
      </div>
      <div>
        <span class="color-white-50">Please contact your platform admin.</span>
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
    <div class="display-box">
      <.location_header tooltip="The devices location is announced by the device after it connects." />

      <div>
        <span class="color-white-50">No location was found for the device.</span>
      </div>
      <div>
        <span class="color-white-50">Please check if the Geo extension has been included if your firmware.</span>
      </div>
    </div>
    """
  end

  # the IP address was a reserved IP (https://en.wikipedia.org/wiki/Reserved_IP_addresses)
  # maps can't be shown for reserved IPs
  def render(%{location: %{"error_code" => _} = location}) do
    assigns = %{location: location}

    ~H"""
    <div class="display-box">
      <.location_header tooltip="The devices location is announced by the device after it connects." />

      <div>
        <span class="color-white-50">An error occurred during location resolution : <%= @location["error_code"] %></span>
      </div>
      <div>
        <span class="color-white-50"><%= @location["error_description"] %></span>
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
      zoom: 10,
      size: "463x250",
      mapbox_access_token: assigns.mapbox_access_token
    }

    ~H"""
    <div class="display-box">
      <.location_header tooltip={"The devices location was determined via #{@source}"} />

      <img width="463px" height="250px" src={"https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v12/static/#{@lng},#{@lat},#{@zoom},0/#{@size}@2x?access_token=#{@mapbox_access_token}"} />
    </div>
    """
  end

  attr(:tooltip, :string)

  defp location_header(assigns) do
    ~H"""
    <div class="help-text mb-1 tooltip-label">
      <span>Device location</span>
      <span class="tooltip-info"></span>
      <span class="tooltip-text"><%= @tooltip %></span>
    </div>
    """
  end
end
