defmodule NervesHubWeb.Live.DeploymentGroups.Show.WorkflowUploadTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo

  setup %{user: user, org_key: org_key, product: product, tmp_dir: tmp_dir} do
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})

    deployment_group =
      Fixtures.deployment_group_fixture(firmware, %{is_active: true, name: "Workflow Group", user: user})

    %{deployment_group: deployment_group}
  end

  defp write(tmp_dir, name, contents) do
    path = Path.join(tmp_dir, name)
    File.write!(path, contents)
    path
  end

  defp settings_path(org, product, deployment_group) do
    "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/settings"
  end

  @tag :tmp_dir
  test "a definition that is not valid JSON says so", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    # A trailing comma after the tags array: the shape of mistake a person makes
    # writing one of these by hand.
    path =
      write(tmp_dir, "trailing-comma.json", """
      {
        "version": 1,
        "steps": [
          {
            "name": "Canary",
            "matching_conditions": {
              "tags": ["canary"],
            }
          }
        ]
      }
      """)

    conn
    |> visit(settings_path(org, product, deployment_group))
    |> upload("Upload Workflow Definition", path)
    |> assert_has("div", text: "could not be read as JSON")

    refute Repo.reload(deployment_group).workflow_definition
  end

  @tag :tmp_dir
  test "a definition the schema rejects says what is wrong", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    path =
      write(tmp_dir, "no-name.json", """
      {"version": 1, "steps": [{"concurrent_updates": 5}]}
      """)

    conn
    |> visit(settings_path(org, product, deployment_group))
    |> upload("Upload Workflow Definition", path)
    |> assert_has("div", text: "not valid")

    refute Repo.reload(deployment_group).workflow_definition
  end

  # Driven through LiveViewTest rather than the page helper: a good upload sends
  # the browser to the deployment group, and the helper carries on talking to the
  # view it just navigated away from.
  test "a valid definition is stored, and takes you to the deployment group", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    {:ok, view, _html} = live(conn, settings_path(org, product, deployment_group))

    contents = ~s({"version": 1, "steps": [{"name": "Canary", "matching_conditions": {"tags": ["canary"]}}]})

    upload =
      file_input(view, "#deployment-form", :workflow_definition, [
        %{name: "good.json", content: contents, type: "application/json"}
      ])

    assert {:error, {:live_redirect, %{to: to}}} = render_upload(upload, "good.json")
    assert to =~ "/deployment_groups/"

    assert %{"steps" => [%{"name" => "Canary"}]} = Repo.reload(deployment_group).workflow_definition
  end

  @tag :tmp_dir
  test "an existing definition can be removed", %{
    conn: conn,
    org: org,
    product: product,
    user: user,
    deployment_group: deployment_group
  } do
    definition = %{"version" => 1, "steps" => [%{"name" => "Canary"}]}

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: definition}, user)

    conn
    |> visit(settings_path(org, product, deployment_group))
    |> click_link("Delete Workflow Definition")
    |> assert_has("div", text: "removed successfully")

    refute Repo.reload(deployment_group).workflow_definition
  end
end
