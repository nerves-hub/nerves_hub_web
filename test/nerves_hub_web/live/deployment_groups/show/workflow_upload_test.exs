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
    |> upload("Upload", path)
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
    |> upload("Upload", path)
    |> assert_has("div", text: "not valid")

    refute Repo.reload(deployment_group).workflow_definition
  end

  @tag :tmp_dir
  test "a valid definition is stored, and its steps listed", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    path =
      write(
        tmp_dir,
        "good.json",
        ~s({"version": 1, "steps": [{"name": "Canary", "matching_conditions": {"tags": ["canary"]}}]})
      )

    conn
    |> visit(settings_path(org, product, deployment_group))
    |> upload("Upload", path)
    |> assert_has("[role=alert]", text: "Workflow saved. It applies from the next release.")
    |> assert_has("#workflow-steps li", text: "Canary")
    |> assert_has("#replace-workflow", text: "Replace")

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
    |> click_button("Remove workflow")
    |> within("#settings-confirm", &click_button(&1, "Remove workflow"))
    |> assert_has("[role=alert]", text: "Workflow removed")
    |> refute_has("#workflow-steps")

    refute Repo.reload(deployment_group).workflow_definition
  end
end
