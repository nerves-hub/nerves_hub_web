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

  describe "pagination" do
    test "shows a next page button when there are more than 25 audit logs", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group,
      user: user
    } do
      Enum.each(1..30, fn i ->
        NervesHub.AuditLogs.audit!(user, deployment_group, "Pagination test entry #{i}")
      end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/activity")
      |> assert_has("div.flex.items-center.gap-6", count: 25)
      |> assert_has("button[phx-value-page=\"2\"]")
    end

    test "clicking next page loads more audit logs", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group,
      user: user
    } do
      Enum.each(1..30, fn i ->
        NervesHub.AuditLogs.audit!(user, deployment_group, "Pagination test entry #{i}")
      end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/activity")
      |> assert_has("button[phx-value-page=\"2\"]")
      |> click_button(~s(button[phx-click="paginate"][phx-value-page="2"]), "2")
      |> assert_path(
        "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.id}/activity",
        query_params: %{"page_number" => "2", "page_size" => "25"}
      )
      |> assert_has("div.flex.items-center.gap-6", count: 6)
    end

    test "changing page size reloads with the correct number of entries", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group,
      user: user
    } do
      Enum.each(1..60, fn i ->
        NervesHub.AuditLogs.audit!(user, deployment_group, "Page size test entry #{i}")
      end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/activity")
      |> click_button("50")
      |> assert_path(
        "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.id}/activity",
        query_params: %{"page_number" => "1", "page_size" => "50"}
      )
      |> assert_has("div.flex.items-center.gap-6", count: 50)
    end
  end
end
