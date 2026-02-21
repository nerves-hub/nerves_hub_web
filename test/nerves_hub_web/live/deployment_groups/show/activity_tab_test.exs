defmodule NervesHubWeb.Live.NewUI.DeploymentGroups.Show.ActivityTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  setup context do
    conn =
      context.conn
      |> visit(
        "/org/#{context.org.name}/#{context.product.name}/deployment_groups/#{context.deployment_group.name}/activity"
      )
      |> assert_has("div", text: "Latest activity")

    %{context | conn: conn}
  end

  test "shows a nice message when there are no audit logs", %{conn: conn} do
    assert_has(conn, "span", text: "No audit logs found for the deployment group.")
  end
end
