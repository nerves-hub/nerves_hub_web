defmodule NervesHubWeb.Components.DeviceLocation do
  use NervesHubWeb, :component

  attr(:connection_metadata, :any)

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
  def render(%{connection_metadata: connection_metadata})
      when not is_map_key(connection_metadata, "location") do
    render(%{connection_metadata: Map.put(connection_metadata, "location", %{})})
  end

  # location information is empty, geo location might not be enabled
  def render(%{connection_metadata: %{"location" => location}} = assigns)
      when map_size(location) == 0 do
    ~H"""
    <div class="display-box">
      <.location_header tooltip="The devices location is determined by looking up the request IP of the device using a GeoIP database." />

      <div>
        <span class="color-white-50">No location was found for the device.</span>
      </div>
      <div>
        <span class="color-white-50">Please check with your platform admin if geo location has been enabled.</span>
      </div>
    </div>
    """
  end

  # the IP address was a reserved IP (https://en.wikipedia.org/wiki/Reserved_IP_addresses)
  # maps can't be shown for reserved IPs
  def render(
        %{connection_metadata: %{"location" => %{"error_code" => "IP_ADDRESS_RESERVED"}}} =
          assigns
      ) do
    assigns = %{
      ip_address: assigns.connection_metadata["request_ip"]
    }

    ~H"""
    <div class="display-box">
      <.location_header tooltip="The devices location is determined by looking up the request IP of the device using a GeoIP database." />

      <div>
        <span class="color-white-50">The IP address is reporting as <%= @ip_address %></span>
      </div>
      <div>
        <span class="color-white-50">A map can't be shown for reserved addresses.</span>
      </div>
    </div>
    """
  end

  # yay, we have a location and map key, lets display a map
  def render(%{connection_metadata: %{"location" => location}} = assigns) do
    assigns = %{
      lat: location["latitude"],
      lng: location["longitude"],
      accuracy_radius: location["accuracy_radius"],
      zoom: 10,
      size: "463x250",
      mapbox_access_token: assigns.mapbox_access_token
    }

    ~H"""
    <div class="display-box">
      <.location_header tooltip={"The devices location is determined by looking up the request IP of the device using a GeoIP database. The reported accuracy radius is #{@accuracy_radius}km."} />

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
