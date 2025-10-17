defmodule NervesHubWeb.Live.NewUI.DeploymentGroups.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.AuditLogs
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  alias NervesHub.Fixtures

  setup context do
    conn =
      context.conn
      |> visit(
        "/org/#{context.org.name}/#{context.product.name}/deployment_groups/#{context.deployment_group.name}/settings"
      )
      |> assert_has("div", text: "General settings")

    %{context | conn: conn}
  end

  test "can update queue management", %{
    conn: conn,
    deployment_group: deployment_group
  } do
    assert deployment_group.queue_management == :FIFO

    conn
    |> select("Queue management", option: "LIFO")
    |> submit()

    assert Repo.reload(deployment_group).queue_management == :LIFO
  end

  test "can update only version", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("Version requirement", with: "1.2.3")
    |> submit()

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.conditions.version == "1.2.3"
  end

  test "can update only tags", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("Tag(s) distributed to", with: "a, b")
    |> submit()

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.conditions.tags == ["a", "b"]
  end

  test "can update tags and version", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("Tag(s) distributed to", with: "a, b")
    |> fill_in("Version requirement", with: "1.2.3")
    |> submit()

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.conditions.tags == ["a", "b"]
    assert deployment_group.conditions.version == "1.2.3"
  end

  test "update the chosen resource, and adds an audit log", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware)

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/settings")
      |> assert_has("div", text: "General settings")
      |> assert_has("a", text: product.name)
      |> fill_in("Name", with: "Moussaka")
      |> fill_in("Tag(s) distributed to", with: "josh, lars")
      |> fill_in("Version requirement", with: "4.3.2")
      |> select("Firmware version", option: String.split(firmware.uuid, "-") |> List.first(), exact_option: false)
      |> click_button("Save changes")

    {:ok, reloaded_deployment_group} =
      ManagedDeployments.get_deployment_group(deployment_group.id)

    conn
    |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/deployment_groups/#{reloaded_deployment_group.name}"))
    |> assert_has("div", text: "Deployment Group updated")

    assert reloaded_deployment_group.name == "Moussaka"
    assert reloaded_deployment_group.conditions.version == "4.3.2"
    assert Enum.sort(reloaded_deployment_group.conditions.tags) == Enum.sort(~w(josh lars))

    [audit_log_one, audit_log_two] = AuditLogs.logs_for(reloaded_deployment_group)

    assert audit_log_one.resource_type == DeploymentGroup
    assert audit_log_two.description =~ ~r/conditions changed/
  end

  test "failed update shows errors", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/settings")
    |> assert_has("div", text: "General settings")
    |> assert_has("a", text: product.name)
    |> fill_in("Version requirement", with: "1.2.3.4.5.6")
    |> click_button("Save changes")
    |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/settings")
    |> assert_has("div", text: "must be valid Elixir version requirement string")
  end

  test "can clear tags and version", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/settings")
    |> assert_has("div", text: "General settings")
    |> fill_in("Tag(s) distributed to", with: "")
    |> fill_in("Version requirement", with: "")
    |> click_button("Save changes")
    |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}"))

    deployment_group = Repo.reload(deployment_group)

    assert deployment_group.conditions.version == ""
    assert deployment_group.conditions.tags == []
  end
end
