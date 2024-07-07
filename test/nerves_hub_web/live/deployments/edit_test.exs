defmodule NervesHubWeb.Live.Deployments.EditTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Fixtures

  test "update the chosen resource, and adds an audit log", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment = Fixtures.deployment_fixture(org, firmware)

    conn =
      conn
      |> visit("/products/#{hashid(product)}/deployments/#{deployment.name}/edit")
      |> assert_has("h1", text: "Edit Deployment")
      |> assert_has("a", text: product.name)
      |> fill_in("Deployment name", with: "Moussaka")
      |> fill_in("Tag(s) distributed to", with: "josh, lars")
      |> fill_in("Version requirement", with: "4.3.2")
      |> fill_in("Firmware version", with: firmware.id)
      |> click_button("Save Change")

    {:ok, reloaded_deployment} = Deployments.get_deployment(product, deployment.id)

    conn
    |> assert_path(
      URI.encode("/products/#{hashid(product)}/deployments/#{reloaded_deployment.name}")
    )
    |> assert_has("div", text: "Deployment updated")

    assert reloaded_deployment.name == "Moussaka"
    assert reloaded_deployment.conditions["version"] == "4.3.2"
    assert Enum.sort(reloaded_deployment.conditions["tags"]) == Enum.sort(~w(josh lars))

    [audit_log_one, audit_log_two] = AuditLogs.logs_for(deployment)

    assert audit_log_one.resource_type == Deployment
    assert audit_log_two.description =~ ~r/removed all devices/
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
    deployment = Fixtures.deployment_fixture(org, firmware)

    conn
    |> visit("/products/#{hashid(product)}/deployments/#{deployment.name}/edit")
    |> assert_has("h1", text: "Edit Deployment")
    |> assert_has("a", text: product.name)
    |> fill_in("Tag(s) distributed to", with: "")
    |> fill_in("Version requirement", with: "")
    |> click_button("Save Change")
    |> assert_path("/products/#{hashid(product)}/deployments/#{deployment.name}/edit")
    |> assert_has("div", text: "should have at least 1 item(s)")
  end
end
