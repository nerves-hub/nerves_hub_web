defmodule NervesHubWeb.Live.DeploymentGroupsSortingTest do
  use NervesHubWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias NervesHub.Fixtures

  describe "deployment group sorting UI" do
    test "NULL device counts appear last when sorting by device count", %{conn: conn} do
      org = Fixtures.org_fixture()
      product = Fixtures.product_fixture(org)
      firmware = Fixtures.firmware_fixture(product)

      # Create deployment groups, some with devices, some without
      dg_with_devices = Fixtures.deployment_group_fixture(product, firmware)
      dg_without_devices = Fixtures.deployment_group_fixture(product, firmware)

      # Add a device to one group
      _device = Fixtures.device_fixture(product, deployment_group: dg_with_devices)

      # Visit the deployments page
      {:ok, view, _html} =
        live(conn, ~p"/org/#{org.name}/#{product.name}/deployment_groups")

      # Click to sort by device count (simulate user click)
      view |> element("th[phx-value-sort='device_count']") |> render_click()

      # Fetch the rendered rows
      rows =
        view
        |> render()
        |> Floki.find("tr[data-deployment-group-id]")
        |> Enum.map(&Floki.text/1)

      # The group with no devices (NULL count) should be last
      assert List.last(rows) =~ dg_without_devices.name
      assert Enum.any?(rows, &String.contains?(&1, dg_with_devices.name))
    end
  end
end
