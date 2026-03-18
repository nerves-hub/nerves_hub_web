defmodule NervesHubWeb.Live.DeploymentGroups.Show.ActivityTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  setup context do
    conn =
      context.conn
      |> visit(
        "/org/#{context.org.name}/#{context.product.name}/deployment_groups/#{context.deployment_group.name}/activity"
      )
      |> assert_has("div", text: "Latest activity")

    %{context | conn: conn}
  end

  test "shows an audit log message saying who created the deployment group", %{conn: conn} do
    assert_has(conn, "div", text: "created deployment group")
  end
end
