defmodule NervesHubWeb.Plugs.DeviceTest do
  use NervesHubWeb.ConnCase, async: true

  import Plug.Test

  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHubWeb.Plugs.Device, as: DevicePlug

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    scope = Scope.for_user(user) |> Scope.put_org(org)

    %{device: device, scope: scope}
  end

  describe "init/1" do
    test "passes opts through unchanged" do
      assert DevicePlug.init(:any) == :any
    end
  end

  describe "call/2 when device is found" do
    test "assigns the device to the conn", %{device: device, scope: scope} do
      conn =
        conn(:get, "/")
        |> Map.put(:params, %{"identifier" => device.identifier})
        |> Plug.Conn.assign(:current_scope, scope)

      result = DevicePlug.call(conn, [])

      refute result.halted
      assert result.assigns.device.id == device.id
    end
  end

  describe "call/2 when device is not found" do
    test "halts with 404 when identifier does not match", %{scope: scope} do
      conn =
        conn(:get, "/")
        |> Map.put(:params, %{"identifier" => "no-such-device"})
        |> Plug.Conn.assign(:current_scope, scope)

      result = DevicePlug.call(conn, [])

      assert result.halted
      assert result.status == 404
    end
  end
end
