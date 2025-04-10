defmodule NervesHubWeb.Live.NewUI.Devices.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures

  alias NervesHub.Repo

  alias NervesHubWeb.Endpoint

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
end
