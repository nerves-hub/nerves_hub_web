defmodule NervesHubWeb.API.ExternalIdentityControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Devices
  alias NervesHub.Devices.ExternalIdentities

  @iroh_console "c8924b6c9b7a8528b1365ebec4b2e43b6edebef684f8521f12b8caaf6e1b2302"
  @iroh_app "5f691e39f55415be337b2e4cc0dd7291586ab7c4356bf32bab60f46fc78f95d5"
  @tailscale String.duplicate("ab", 32)

  setup %{org: org, product: product} do
    {:ok, device} =
      Devices.create_device(%{
        identifier: "device-1234",
        description: "test device",
        tags: ["test"],
        org_id: org.id,
        product_id: product.id
      })

    [device: device]
  end

  defp path(conn, org, product, device, params \\ []) do
    Routes.api_external_identity_path(conn, :index, org.name, product.name, device.identifier, params)
  end

  describe "index" do
    test "is empty for a device that has reported nothing", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device))

      assert json_response(conn, 200)["data"] == []
    end

    test "lists what the device reported", %{conn: conn, org: org, product: product, device: device} do
      {:ok, _} =
        ExternalIdentities.report(device.id, "iroh", %{
          identifier: @iroh_console,
          details: %{"relay" => "https://relay.example.com"}
        })

      conn = get(conn, path(conn, org, product, device))

      assert [identity] = json_response(conn, 200)["data"]
      assert identity["identifier"] == @iroh_console
      assert identity["service"] == "iroh"
      assert identity["instance"] == "default"
      assert identity["source"] == "device_reported"
      assert identity["details"] == %{"relay" => "https://relay.example.com"}
      assert identity["last_reported_at"]
    end

    test "does not list another device's", %{conn: conn, org: org, product: product, device: device} do
      {:ok, other} =
        Devices.create_device(%{identifier: "device-5678", org_id: org.id, product_id: product.id})

      {:ok, _} = ExternalIdentities.report(other.id, "iroh", %{identifier: @iroh_console})

      conn = get(conn, path(conn, org, product, device))

      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "filtering" do
    setup %{device: device} do
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: @iroh_console, instance: "console"})
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: @iroh_app, instance: "application"})
      {:ok, _} = ExternalIdentities.report(device.id, "tailscale", %{identifier: @tailscale})
      :ok
    end

    test "narrows to one service", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, service: "iroh"))

      identifiers = for i <- json_response(conn, 200)["data"], do: i["identifier"]
      assert Enum.sort(identifiers) == Enum.sort([@iroh_console, @iroh_app])
    end

    test "narrows to one endpoint of a service", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, service: "iroh", instance: "console"))

      assert [%{"identifier" => @iroh_console}] = json_response(conn, 200)["data"]
    end

    test "an instance on its own still narrows", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, instance: "application"))

      assert [%{"identifier" => @iroh_app}] = json_response(conn, 200)["data"]
    end

    test "an instance nothing uses is empty rather than everything", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn = get(conn, path(conn, org, product, device, instance: "nope"))

      assert json_response(conn, 200)["data"] == []
    end

    test "refuses a service this NervesHub does not know", %{conn: conn, org: org, product: product, device: device} do
      # Ignoring it would answer a typo with every identity the device holds,
      # which reads as keys on a network it has never touched.
      conn = get(conn, path(conn, org, product, device, service: "zerotier"))

      assert json_response(conn, 422)["errors"]["detail"] =~ "not a service"
    end

    test "an empty filter is no filter", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, service: "", instance: ""))

      assert length(json_response(conn, 200)["data"]) == 3
    end
  end
end
