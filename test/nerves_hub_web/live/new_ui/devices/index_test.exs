defmodule NervesHubWeb.Live.NewUI.Devices.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  alias NervesHubWeb.Endpoint

  test "shows a loading message (async loading)", %{conn: conn, fixture: fixture} do
    %{device: device, org: org, product: product} = fixture

    {:ok, lv, html} =
      conn
      |> put_session("new_ui", true)
      |> live("/org/#{org.name}/#{product.name}/devices")

    assert html =~ "Loading..."

    assert render_async(lv) =~ device.identifier
  end

  describe "bulk adding devices to deployment group" do
    test "add multiple devices to deployment in new UI",
         %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        firmware: firmware,
        deployment_group: deployment_group
      } = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)
      Endpoint.subscribe("device:#{device.id}")
      Endpoint.subscribe("device:#{device2.id}")

      refute device.deployment_id
      refute device2.deployment_id

      conn
      |> put_session("new_ui", true)
      |> visit(
        "/org/#{org.name}/#{product.name}/devices?platform=#{deployment_group.firmware.platform}"
      )
      |> assert_has("div", text: "2", timeout: 1000)
      |> check("Select all devices")
      |> assert_has("div", text: "2 devices selected")
      |> within("form#deployment-move", fn session ->
        session
        |> select("Deployment Group",
          option: deployment_group.name,
          exact_option: false
        )
        |> submit()
      end)
      |> assert_has("div", text: "2 devices added to deployment")

      assert_receive %{event: "devices/updated"}
      assert_receive %{event: "devices/updated"}

      assert Repo.reload(device) |> Map.get(:deployment_id)
      assert Repo.reload(device2) |> Map.get(:deployment_id)
    end
  end

  describe "filtering devices" do
    test "by platform", %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        user: user
      } = fixture

      org_key = Fixtures.org_key_fixture(org, user)
      foo_firmware = Fixtures.firmware_fixture(org_key, product, %{platform: "foo"})
      device2 = Fixtures.device_fixture(org, product, foo_firmware)

      conn
      |> put_session("new_ui", true)
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> assert_has("a", text: device2.identifier)
      |> select("Platform", option: "foo")
      |> assert_has("a", text: device2.identifier, timeout: 1000)
      |> refute_has("a", text: device.identifier)
      |> select("Platform", option: "platform")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> refute_has("a", text: device2.identifier)
    end
  end

  describe "pagination" do
    test "no pagination when less than 25 devices", %{conn: conn, fixture: fixture} do
      %{
        org: org,
        product: product
      } = fixture

      conn
      |> put_session("new_ui", true)
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> refute_has("button", text: "25", timeout: 1000)
    end

    test "pagination with more than 25 devices", %{conn: conn, fixture: fixture} do
      %{
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      for _i <- 1..26 do
        Fixtures.device_fixture(org, product, firmware)
      end

      devices = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)
      [first_device | _] = devices |> Enum.sort_by(& &1.identifier)

      conn
      |> put_session("new_ui", true)
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
      |> assert_has("button", text: "25", timeout: 1000)
      |> refute_has("button", text: "50", timeout: 1000)
      |> assert_has("button", text: "2", timeout: 1000)
      |> click_button("button[phx-click='paginate'][phx-value-page='2']", "2")
      |> refute_has("a", text: first_device.identifier, timeout: 1000)
      |> click_button("button[phx-click='paginate'][phx-value-page='1']", "1")
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
    end

    test "pagination with more than 50 devices", %{conn: conn, fixture: fixture} do
      %{
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      for _i <- 1..51 do
        Fixtures.device_fixture(org, product, firmware)
      end

      devices = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)
      [first_device | _] = devices |> Enum.sort_by(& &1.identifier)

      conn
      |> put_session("new_ui", true)
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
      |> assert_has("button", text: "25", timeout: 1000)
      |> assert_has("button", text: "50", timeout: 1000)
      |> assert_has("button", text: "2", timeout: 1000)
      |> click_button("button[phx-click='paginate'][phx-value-page='2']", "2")
      |> refute_has("a", text: first_device.identifier, timeout: 1000)
      |> click_button("button[phx-click='paginate'][phx-value-page='3']", "3")
      |> refute_has("a", text: first_device.identifier, timeout: 1000)
    end
  end
end
