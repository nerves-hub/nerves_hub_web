defmodule NervesHubWeb.API.ScriptControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Fixtures

  setup context do
    org_key = Fixtures.org_key_fixture(context.org, context.user)
    firmware = Fixtures.firmware_fixture(org_key, context.product)
    device = Fixtures.device_fixture(context.org, context.product, firmware)

    Map.put(context, :device, device)
  end

  describe "index" do
    test "lists scripts", %{conn: conn, product: product, device: device, user: user} do
      script = Fixtures.support_script_fixture(product, user)
      conn = get(conn, Routes.api_script_path(conn, :index, device))
      data = [script_response] = json_response(conn, 200)["data"]
      assert Enum.count(data) == 1
      assert script_response["id"] == script.id
    end
  end
end
