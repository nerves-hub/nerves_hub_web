defmodule NervesHubWeb.API.DeploymentControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.{AuditLogs, Deployments.Deployment, Fixtures}

  describe "index" do
    test "lists all deployments", %{conn: conn, org: org, product: product} do
      conn = get(conn, Routes.api_deployment_path(conn, :index, org.name, product.name))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create deployment" do
    setup context do
      org_key = Fixtures.org_key_fixture(context.org, context.user)
      firmware = Fixtures.firmware_fixture(org_key, context.product)

      params = %{
        name: "test",
        org_id: context.org.id,
        firmware: firmware.uuid,
        firmware_id: firmware.id,
        conditions: %{
          version: "",
          tags: ["test"]
        },
        is_active: false
      }

      [params: params, firmware: firmware, org_key: org_key]
    end

    test "renders deployment when data is valid", %{
      conn: conn,
      org: org,
      params: params,
      product: product
    } do
      conn = post(conn, Routes.api_deployment_path(conn, :create, org.name, product.name), params)
      assert json_response(conn, 201)["data"]

      conn =
        get(conn, Routes.api_deployment_path(conn, :show, org.name, product.name, params.name))

      assert json_response(conn, 200)["data"]["name"] == params.name
    end

    test "audits on success", %{
      conn: conn,
      org: org,
      params: params,
      product: product,
      user: user
    } do
      conn = post(conn, Routes.api_deployment_path(conn, :create, org.name, product.name), params)
      assert json_response(conn, 201)["data"]

      [audit_log] = AuditLogs.logs_by(user)
      assert audit_log.resource_type == Deployment
    end

    test "renders errors when data is invalid", %{conn: conn, org: org, product: product} do
      conn = post(conn, Routes.api_deployment_path(conn, :create, org.name, product.name))
      assert json_response(conn, 500)["errors"] != %{}
    end
  end

  describe "update deployment" do
    setup [:create_deployment]

    test "renders deployment when data is valid", %{
      conn: conn,
      deployment: deployment,
      org: org,
      product: product
    } do
      path = Routes.api_deployment_path(conn, :update, org.name, product.name, deployment.name)
      conn = put(conn, path, deployment: %{"is_active" => true})
      assert %{"is_active" => true} = json_response(conn, 200)["data"]

      path = Routes.api_deployment_path(conn, :show, org.name, product.name, deployment.name)
      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["is_active"]
    end

    test "can use state to set is_active", %{
      conn: conn,
      deployment: deployment,
      org: org,
      product: product
    } do
      path = Routes.api_deployment_path(conn, :update, org.name, product.name, deployment.name)
      refute deployment.is_active
      conn = put(conn, path, deployment: %{"state" => "on"})
      assert %{"is_active" => true, "state" => "on"} = json_response(conn, 200)["data"]

      path = Routes.api_deployment_path(conn, :show, org.name, product.name, deployment.name)
      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["is_active"]
      assert json_response(conn, 200)["data"]["state"] == "on"
    end

    test "audits on success", %{conn: conn, deployment: deployment, org: org, product: product} do
      path = Routes.api_deployment_path(conn, :update, org.name, product.name, deployment.name)
      conn = put(conn, path, deployment: %{"is_active" => true})
      assert json_response(conn, 200)["data"]

      [audit_log] = AuditLogs.logs_for(deployment)
      assert audit_log.resource_type == Deployment
    end

    test "renders errors when data is invalid", %{
      conn: conn,
      deployment: deployment,
      org: org,
      product: product
    } do
      path = Routes.api_deployment_path(conn, :update, org.name, product.name, deployment.name)
      conn = put(conn, path, deployment: %{is_active: "1234"})
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete deployment" do
    setup [:create_deployment]

    test "deletes chosen deployment", %{
      conn: conn,
      org: org,
      product: product,
      deployment: deployment
    } do
      conn =
        delete(
          conn,
          Routes.api_deployment_path(conn, :delete, org.name, product.name, deployment.name)
        )

      assert response(conn, 204)

      conn =
        get(
          conn,
          Routes.api_deployment_path(conn, :show, org.name, product.name, deployment.name)
        )

      assert response(conn, 404)
    end
  end

  defp create_deployment(%{user: user, org: org, product: product}) do
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment = Fixtures.deployment_fixture(org, firmware)
    {:ok, %{deployment: deployment}}
  end
end
