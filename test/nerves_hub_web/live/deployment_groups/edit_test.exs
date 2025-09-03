defmodule NervesHubWeb.Live.DeploymentGroups.EditTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  test "update the chosen resource, and adds an audit log", %{
    conn: conn,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir,
    user: user
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/edit")
      |> assert_has("h1", text: "Edit Deployment Group")
      |> assert_has("a", text: product.name)
      |> fill_in("Deployment Group name", with: "Moussaka")
      |> fill_in("Tag(s) distributed to", with: "josh, lars")
      |> fill_in("Version requirement", with: "4.3.2")
      |> select("Firmware version", option: firmware.uuid, exact_option: false)
      |> click_button("Save Change")

    {:ok, reloaded_deployment_group} =
      ManagedDeployments.get_deployment_group(deployment_group.id)

    conn
    |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/deployment_groups/#{reloaded_deployment_group.name}"))
    |> assert_has("div", text: "Deployment Group updated")

    assert reloaded_deployment_group.name == "Moussaka"
    assert reloaded_deployment_group.conditions["version"] == "4.3.2"
    assert Enum.sort(reloaded_deployment_group.conditions["tags"]) == Enum.sort(~w(josh lars))

    [audit_log_one, audit_log_two] = AuditLogs.logs_for(reloaded_deployment_group)

    assert audit_log_one.resource_type == DeploymentGroup
    assert audit_log_two.description =~ ~r/conditions changed/
  end

  test "failed update shows errors", %{
    conn: conn,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir,
    user: user
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/edit")
    |> assert_has("h1", text: "Edit Deployment Group")
    |> assert_has("a", text: product.name)
    |> fill_in("Version requirement", with: "1.2.3.4.5.6")
    |> click_button("Save Change")
    |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/edit")
    |> assert_has("div", text: "must be valid Elixir version requirement string")
  end

  test "can clear tags and version", %{
    conn: conn,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir,
    user: user
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/edit")
    |> assert_has("h1", text: "Edit Deployment Group")
    |> assert_has("a", text: product.name)
    |> fill_in("Tag(s) distributed to", with: "")
    |> fill_in("Version requirement", with: "")
    |> click_button("Save Change")
    |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}"))

    assert Repo.reload(deployment_group) |> Map.get(:conditions) == %{
             "tags" => [],
             "version" => ""
           }
  end
end
