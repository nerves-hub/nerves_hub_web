defmodule NervesHubWeb.Live.DeploymentGroups.Show.ActivityTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Repo
  alias NervesHubWeb.Components.DeploymentGroupPage.Activity

  setup context do
    path =
      "/org/#{context.org.name}/#{context.product.name}/deployment_groups/#{context.deployment_group.name}/activity"

    conn =
      context.conn
      |> visit(path)
      |> assert_has("#deployment-group-activity")

    %{context | conn: conn}
    |> Map.put(:path, path)
  end

  test "shows an audit log message saying who created the deployment group", %{conn: conn, user: user} do
    conn
    |> assert_has("[data-activity-entry]", text: "#{user.name} created deployment group")
    |> assert_has("#deployment-group-activity h2", text: "Activity")
  end

  test "puts a system entry's first line over the rest, under the workflow glyph", %{
    conn: conn,
    path: path,
    deployment_group: deployment_group
  } do
    :ok =
      AuditLogs.audit!(deployment_group, deployment_group, """
      Workflow step 2 (Sites) failed for deployment group #{deployment_group.name}.
      3 device(s) could not take the update.
      No further devices will be updated for this release.
      """)

    conn
    |> visit(path)
    |> within("[data-activity-entry]:first-child", fn session ->
      session
      |> assert_has(".lucide-workflow--bold")
      |> assert_has("p",
        text: "Workflow step 2 (Sites) failed for deployment group #{deployment_group.name}.",
        exact: true
      )
      |> assert_has("p",
        text: "3 device(s) could not take the update. No further devices will be updated for this release.",
        exact: true
      )
    end)
  end

  test "names the device an entry written before templates is about", %{
    conn: conn,
    path: path,
    org: org,
    product: product,
    device: device,
    deployment_group: deployment_group
  } do
    :ok = AuditLogs.audit!(device, deployment_group, "Device no longer matches deployment group")

    conn
    |> visit(path)
    |> assert_has("[data-activity-entry] a[href='/org/#{org.name}/#{product.name}/devices/#{device.identifier}']",
      text: device.identifier
    )
    |> assert_has("[data-activity-entry]", text: "Device no longer matches deployment group")
  end

  describe "an entry written from a template" do
    test "names the device once, linked, inside the text", %{
      conn: conn,
      path: path,
      org: org,
      product: product,
      device: device,
      deployment_group: deployment_group
    } do
      :ok = DeploymentGroupTemplates.audit_deployment_mismatch(device, deployment_group, "mismatched version")

      conn
      |> visit(path)
      |> assert_has(
        "[data-activity-entry] a[data-ref=device][href='/org/#{org.name}/#{product.name}/devices/#{device.identifier}']",
        text: device.identifier,
        count: 1
      )
      |> assert_has("[data-activity-entry]",
        text: "Device #{device.identifier} no longer matches deployment group #{deployment_group.name}'s requirements"
      )
    end

    test "names the user as they are now, and the group without a link to its own page", %{
      conn: conn,
      path: path,
      user: user,
      deployment_group: deployment_group
    } do
      Repo.update!(Ecto.Changeset.change(user, name: "Renamed"))

      conn
      |> visit(path)
      |> assert_has("[data-activity-entry] span[data-ref=user]", text: "Renamed")
      |> assert_has("[data-activity-entry] span[data-ref=deployment_group]", text: deployment_group.name)
      |> refute_has("[data-activity-entry] a[data-ref=deployment_group]")
    end

    test "splits the template into headline and detail", %{
      conn: conn,
      path: path,
      deployment_group: deployment_group
    } do
      step = %DeploymentWorkflowStep{number: 2, name: "Sites"}
      :ok = DeploymentGroupTemplates.audit_workflow_step_failed(deployment_group, step, 3)

      conn
      |> visit(path)
      |> within("[data-activity-entry]:first-child", fn session ->
        session
        |> assert_has("p",
          text: "Workflow step 2 (Sites) failed for deployment group #{deployment_group.name}.",
          exact: true
        )
        |> assert_has("p", text: "3 device(s) could not take the update", exact: false)
      end)
    end
  end

  describe "split_description/1" do
    test "leaves a one-line description whole" do
      assert Activity.split_description("User Ann updated deployment group G") ==
               {"User Ann updated deployment group G", nil}
    end

    test "joins the lines after the first into one" do
      assert Activity.split_description("First.\nSecond\nthird.\n") == {"First.", "Second third."}
    end
  end

  describe "pagination" do
    setup %{user: user, deployment_group: deployment_group} do
      Enum.each(1..30, fn i ->
        AuditLogs.audit!(user, deployment_group, "Pagination test entry #{i}")
      end)
    end

    test "shows 25 entries and a next page button", %{conn: conn, path: path} do
      conn
      |> visit(path)
      |> assert_has("#deployment-group-activity span", text: "Page 1 of 2")
      |> assert_has("[data-activity-entry]", count: 25)
      |> assert_has("button[phx-value-page=\"2\"]")
    end

    test "clicking next page loads more audit logs", %{
      conn: conn,
      path: path,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      encoded_name = URI.encode(deployment_group.name)

      conn
      |> visit(path)
      |> click_button(~s(button[phx-click="paginate"][phx-value-page="2"]), "2")
      |> assert_path(
        "/org/#{org.name}/#{product.name}/deployment_groups/#{encoded_name}/activity",
        query_params: %{"page_number" => "2", "page_size" => "25"}
      )
      |> assert_has("[data-activity-entry]", count: 6)
    end

    test "opens on the page the URL asks for, and stays there as the page refreshes", %{
      conn: conn,
      path: path
    } do
      conn
      |> visit(path <> "?page_number=2&page_size=25")
      |> assert_has("[data-activity-entry]", count: 6)
      |> unwrap(fn view ->
        send(view.pid, :refresh)
        render(view)
      end)
      |> assert_has("[data-activity-entry]", count: 6)
      |> assert_has("button[aria-current=page]", text: "2")
    end

    test "changing page size reloads with the correct number of entries", %{
      conn: conn,
      path: path,
      org: org,
      product: product,
      user: user,
      deployment_group: deployment_group
    } do
      Enum.each(1..30, fn i ->
        AuditLogs.audit!(user, deployment_group, "Page size test entry #{i}")
      end)

      encoded_name = URI.encode(deployment_group.name)

      conn
      |> visit(path)
      |> unwrap(&(&1 |> form("#activity-pager-page-size", %{"page-size" => "50"}) |> render_change()))
      |> assert_path(
        "/org/#{org.name}/#{product.name}/deployment_groups/#{encoded_name}/activity",
        query_params: %{"page_number" => "1", "page_size" => "50"}
      )
      |> assert_has("[data-activity-entry]", count: 50)
    end

    test "ignores a page size the pager doesn't offer", %{conn: conn, path: path} do
      conn
      |> visit(path <> "?page_size=10000")
      |> assert_has("[data-activity-entry]", count: 25)
    end
  end
end
