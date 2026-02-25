defmodule NervesHubWeb.Live.NewUI.DeploymentGroups.Show.ReleasesTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  setup context do
    %{
      org: org,
      product: product,
      deployment_group: deployment_group
    } = context

    conn =
      context.conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
      |> assert_has("div", text: "Release History")

    %{context | conn: conn}
  end

  test "shows created releases", %{conn: conn} do
    conn
    |> assert_has("th", text: "Released")
    |> assert_has("th", text: "Firmware Version")
    |> assert_has("td", text: "1.0.0")
  end
end
