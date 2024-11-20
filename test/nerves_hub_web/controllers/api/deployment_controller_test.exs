defmodule NervesHubWeb.API.DeploymentGroupControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments.DeploymentGroup

  describe "index" do
    test "lists all deployments", %{conn: conn, org: org, product: product} do
      conn = get(conn, Routes.api_deployment_group_path(conn, :index, org.name, product.name))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create deployment group" do
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

    test "renders deployment group when data is valid", %{
      conn: conn,
      org: org,
      params: params,
      product: product
    } do
      conn =
        post(
          conn,
          Routes.api_deployment_group_path(conn, :create, org.name, product.name),
          params
        )

      assert json_response(conn, 201)["data"]

      conn =
        get(
          conn,
          Routes.api_deployment_group_path(conn, :show, org.name, product.name, params.name)
        )

      assert json_response(conn, 200)["data"]["name"] == params.name
    end

    test "audits on success", %{
      conn: conn,
      org: org,
      params: params,
      product: product,
      user: user
    } do
      conn =
        post(
          conn,
          Routes.api_deployment_group_path(conn, :create, org.name, product.name),
          params
        )

      assert json_response(conn, 201)["data"]

      [audit_log] = AuditLogs.logs_by(user)
      assert audit_log.resource_type == DeploymentGroup
    end

    test "renders errors when data is invalid", %{conn: conn, org: org, product: product} do
      conn = post(conn, Routes.api_deployment_group_path(conn, :create, org.name, product.name))
      assert json_response(conn, 500)["errors"] != %{}
    end
  end

  describe "update deployment group" do
    setup [:create_deployment_group]

    test "renders deployment group when data is valid", %{
      conn: conn,
      deployment_group: deployment_group,
      org: org,
      product: product
    } do
      path =
        Routes.api_deployment_group_path(
          conn,
          :update,
          org.name,
          product.name,
          deployment_group.name
        )

      conn = put(conn, path, deployment: %{"is_active" => true})
      assert %{"is_active" => true} = json_response(conn, 200)["data"]

      path =
        Routes.api_deployment_group_path(
          conn,
          :show,
          org.name,
          product.name,
          deployment_group.name
        )

      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["is_active"]
    end

    test "can use state to set is_active", %{
      conn: conn,
      deployment_group: deployment_group,
      org: org,
      product: product
    } do
      path =
        Routes.api_deployment_group_path(
          conn,
          :update,
          org.name,
          product.name,
          deployment_group.name
        )

      refute deployment_group.is_active
      conn = put(conn, path, deployment: %{"state" => "on"})
      assert %{"is_active" => true, "state" => "on"} = json_response(conn, 200)["data"]

      path =
        Routes.api_deployment_group_path(
          conn,
          :show,
          org.name,
          product.name,
          deployment_group.name
        )

      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["is_active"]
      assert json_response(conn, 200)["data"]["state"] == "on"
    end

    test "audits on success", %{
      conn: conn,
      deployment_group: deployment_group,
      org: org,
      product: product
    } do
      path =
        Routes.api_deployment_group_path(
          conn,
          :update,
          org.name,
          product.name,
          deployment_group.name
        )

      conn = put(conn, path, deployment: %{"is_active" => true})
      assert json_response(conn, 200)["data"]

      [audit_log] = AuditLogs.logs_for(deployment_group)
      assert audit_log.resource_type == DeploymentGroup
    end

    test "renders errors when data is invalid", %{
      conn: conn,
      deployment_group: deployment_group,
      org: org,
      product: product
    } do
      path =
        Routes.api_deployment_group_path(
          conn,
          :update,
          org.name,
          product.name,
          deployment_group.name
        )

      conn = put(conn, path, deployment: %{is_active: "1234"})
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete deployment group" do
    setup [:create_deployment_group]

    test "deletes chosen deployment group", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      conn =
        delete(
          conn,
          Routes.api_deployment_group_path(
            conn,
            :delete,
            org.name,
            product.name,
            deployment_group.name
          )
        )

      assert response(conn, 204)

      conn =
        get(
          conn,
          Routes.api_deployment_group_path(
            conn,
            :show,
            org.name,
            product.name,
            deployment_group.name
          )
        )

      assert response(conn, 404)
    end
  end

  defp create_deployment_group(%{user: user, org: org, product: product}) do
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)
    {:ok, %{deployment_group: deployment_group}}
  end
end
