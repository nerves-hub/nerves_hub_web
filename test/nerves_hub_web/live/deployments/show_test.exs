defmodule NervesHubWeb.Live.Deployments.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.Deployments
  alias NervesHub.Fixtures

  test "shows the deployment", %{
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
    |> visit("/org/#{org.name}/#{product.name}/deployments/#{deployment.name}")
    |> assert_has("h1", text: deployment.name)
    |> assert_has("p.deployment-state", text: "Off")
    |> then(fn conn ->
      for tag <- deployment.conditions["tags"] do
        assert_has(conn, "span", text: tag)
      end

      conn
    end)
  end

  test "you can delete a deployment", %{
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
    |> visit("/org/#{org.name}/#{product.name}/deployments/#{deployment.name}")
    |> assert_has("h1", text: deployment.name)
    |> click_link("Delete")
    |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/deployments"))
    |> assert_has("div", text: "Deployment successfully deleted")

    assert Deployments.get_deployment(product, deployment.id) == {:error, :not_found}

    logs = AuditLogs.logs_for(deployment)

    assert List.last(logs).description =~ ~r/deleted deployment/
  end

  test "you can toggle the deployment being on or off", %{
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
    |> visit("/org/#{org.name}/#{product.name}/deployments/#{deployment.name}")
    |> assert_has("h1", text: deployment.name)
    |> click_link("Turn On")
    |> assert_path("/org/#{org.name}/#{product.name}/deployments/#{deployment.name}")
    |> then(fn conn ->
      {:ok, reloaded_deployment} = Deployments.get_deployment(product, deployment.id)

      assert reloaded_deployment.is_active
      assert_has(conn, "span", text: "Turn Off")

      logs = AuditLogs.logs_for(deployment)
      assert Enum.count(logs) == 1
      assert List.last(logs).description =~ ~r/marked deployment/
      conn
    end)
    |> click_link("Turn Off")
    |> assert_path("/org/#{org.name}/#{product.name}/deployments/#{deployment.name}")
    |> then(fn conn ->
      {:ok, reloaded_deployment} = Deployments.get_deployment(product, deployment.id)

      refute reloaded_deployment.is_active
      assert_has(conn, "span", text: "Turn On")

      logs = AuditLogs.logs_for(deployment)
      assert Enum.count(logs) == 3
      assert List.last(logs).description =~ ~r/marked deployment/
      conn
    end)
  end
end
