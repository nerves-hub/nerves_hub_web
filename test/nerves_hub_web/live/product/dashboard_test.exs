defmodule NervesHubWeb.Live.Product.DashboardTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHubWeb.Endpoint

  alias Phoenix.Socket.Broadcast

  @valid_location %{
    "latitude" => 60.6204,
    "longitude" => 16.7697,
    "source" => "geoip"
  }

  @invalid_location %{
    "latitude" => 60.6204,
    "source" => "geoip"
  }

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  describe "dashboard map" do
    test "assert devices with location data renders map and marker info", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      assert {:ok, %Device{}} =
               Devices.update_device(device, %{
                 connection_metadata: %{"location" => @valid_location}
               })

      conn
      |> visit("/org/#{org.name}/#{product.name}/dashboard")
      |> assert_has("#map")
      |> assert_has("#map-markers")
    end

    test "assert page render without locations ", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      assert device.connection_metadata["location"] == nil

      conn
      |> visit("/org/#{org.name}/#{product.name}/dashboard")
      |> assert_has("h3", text: "#{product.name} doesn’t have any devices with location data.")
    end

    test "assert page render without devices", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      assert {:ok, _} = Devices.delete_device(device)

      conn
      |> visit("/org/#{org.name}/#{product.name}/dashboard")
      |> assert_has("h3", text: "#{product.name} doesn’t have any devices yet.")
    end

    test "assert page still render with invalid location data", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      assert {:ok, %Device{}} =
               Devices.update_device(device, %{
                 connection_metadata: %{"location" => @invalid_location}
               })

      conn
      |> visit("/org/#{org.name}/#{product.name}/dashboard")
      |> assert_has("h3", text: "#{product.name} doesn’t have any devices with location data.")
    end

    test "handle_info - location:update", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/dashboard")
      |> assert_has("#map")
      |> assert_has("h3", text: "#{product.name} doesn’t have any devices with location data.")
      |> unwrap(fn view ->
        {:ok, _} =
          Devices.update_device(device, %{connection_metadata: %{"location" => @valid_location}})

        send(view.pid, %Broadcast{event: "location:updated", payload: @valid_location})
        render(view)
      end)
      |> refute_has("h3", text: "#{product.name} doesn’t have any devices with location data.")
      |> assert_has("#map-markers")
    end
  end
end
