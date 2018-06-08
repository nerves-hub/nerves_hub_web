defmodule NervesHubWeb.DeploymentControllerTest do
  use NervesHubWeb.ConnCase.Browser

  alias NervesHub.Fixtures
  alias NervesHub.Deployments

  describe "index" do
    test "lists all deployments", %{conn: conn} do
      conn = get(conn, deployment_path(conn, :index))
      assert html_response(conn, 200) =~ "Deployments"
    end
  end

  describe "new deployment" do
    test "renders form with valid request params", %{conn: conn, current_tenant: tenant} do
      firmware = Fixtures.firmware_fixture(tenant)
      conn = get(conn, deployment_path(conn, :new), deployment: %{firmware_id: firmware.id})

      assert html_response(conn, 200) =~ "Create Deployment"
    end

    test "redirects with invalid firmware", %{conn: conn} do
      conn = get(conn, deployment_path(conn, :new), deployment: %{firmware_id: -1})

      assert redirected_to(conn, 302) =~ deployment_path(conn, :new)
    end

    test "redirects form with no firmware", %{conn: conn} do
      conn = get(conn, deployment_path(conn, :new))

      assert redirected_to(conn, 302) =~ firmware_path(conn, :index)
    end
  end

  describe "create deployment" do
    test "redirects to index when data is valid", %{conn: conn, current_tenant: tenant} do
      firmware = Fixtures.firmware_fixture(tenant)

      deployment_params = %{
        firmware_id: firmware.id,
        tenant_id: tenant.id,
        name: "Test Deployment ABC",
        tags: "beta, beta-edge",
        version: "< 1.0.0",
        is_active: true
      }

      # check that we end up in the right place
      create_conn = post(conn, deployment_path(conn, :create), deployment: deployment_params)
      assert redirected_to(create_conn, 302) =~ deployment_path(conn, :index)

      # check that the proper creation side effects took place
      conn = get(conn, deployment_path(conn, :index))
      assert html_response(conn, 200) =~ deployment_params.name
      assert html_response(conn, 200) =~ "Inactive"
    end
  end

  describe "edit deployment" do
    test "edits the chosen resource", %{conn: conn, current_tenant: tenant} do
      firmware = Fixtures.firmware_fixture(tenant)
      deployment = Fixtures.deployment_fixture(tenant, firmware)

      conn = get(conn, deployment_path(conn, :edit, deployment))
      assert html_response(conn, 200) =~ "Edit"
    end
  end

  describe "update deployment" do
    test "update the chosen resource", %{conn: conn, current_tenant: tenant} do
      firmware = Fixtures.firmware_fixture(tenant)
      deployment = Fixtures.deployment_fixture(tenant, firmware)

      conn =
        put(
          conn,
          deployment_path(conn, :update, deployment),
          deployment: %{
            "version" => "4.3.2",
            "tags" => "new, tags, now",
            "name" => "not original",
            "firmware_id" => firmware.id
          }
        )

      {:ok, reloaded_deployment} = Deployments.get_deployment(tenant, deployment.id)

      assert redirected_to(conn, 302) =~ deployment_path(conn, :show, deployment)
      assert reloaded_deployment.name == "not original"
      assert reloaded_deployment.conditions["version"] == "4.3.2"
      assert Enum.sort(reloaded_deployment.conditions["tags"]) == Enum.sort(~w(new tags now))
    end
  end

  describe "delete deployment" do
    test "deletes chosen resource", %{conn: conn, current_tenant: tenant} do
      firmware = Fixtures.firmware_fixture(tenant)
      deployment = Fixtures.deployment_fixture(tenant, firmware)

      conn = delete(conn, deployment_path(conn, :delete, deployment))
      assert redirected_to(conn) == deployment_path(conn, :index)
      assert Deployments.get_deployment(tenant, deployment.id) == {:error, :not_found}
    end
  end
end
