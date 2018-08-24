defmodule NervesHubAPIWeb.DeploymentControllerTest do
  use NervesHubAPIWeb.ConnCase

  alias NervesHubCore.Fixtures

  describe "index" do
    test "lists all deployments", %{conn: conn, org: org, product: product} do
      conn = get(conn, deployment_path(conn, :index, org.name, product.name))
      assert json_response(conn, 200)["data"] == []
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
      path = deployment_path(conn, :update, org.name, product.name, deployment.name)
      conn = put(conn, path, deployment: %{"is_active" => true})
      assert %{"is_active" => true} = json_response(conn, 200)["data"]

      conn = build_auth_conn()
      path = deployment_path(conn, :show, org.name, product.name, deployment.name)
      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["is_active"]
    end

    test "renders errors when data is invalid", %{
      conn: conn,
      deployment: deployment,
      org: org,
      product: product
    } do
      path = deployment_path(conn, :update, org.name, product.name, deployment.name)
      conn = put(conn, path, deployment: %{is_active: "1234"})
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  defp create_deployment(%{org: org, product: product}) do
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment = Fixtures.deployment_fixture(firmware)
    {:ok, %{deployment: deployment}}
  end
end
