defmodule NervesHubWeb.DeviceControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures

  setup %{user: user, org: org} do
    [product: Fixtures.product_fixture(user, org)]
  end

  describe "console" do
    test "shows information about device", %{conn: conn, user: user, org: org, product: product} do
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/console")
      |> assert_has("p", text: "Console")
      |> assert_has("p", text: "Chat")
    end
  end
end
