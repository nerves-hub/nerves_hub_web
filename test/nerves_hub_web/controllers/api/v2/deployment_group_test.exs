defmodule NervesHubWeb.API.V2.DeploymentGroupTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures

  setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware)

    [deployment_group: deployment_group, firmware: firmware, org_key: org_key]
  end

  describe "index" do
    test "lists deployment groups", %{conn: conn, deployment_group: dg} do
      conn = get(conn, "/api/v2/deployment-groups")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      names = Enum.map(resp["data"], & &1["attributes"]["name"])
      assert dg.name in names
    end
  end

  describe "create" do
    test "creates a deployment group", %{conn: conn, org: org, product: product, firmware: firmware} do
      conn =
        post(conn, "/api/v2/deployment-groups", %{
          "data" => %{
            "type" => "deployment-group",
            "attributes" => %{
              "name" => "ash-deployment",
              "firmware_id" => firmware.id,
              "product_id" => product.id,
              "org_id" => org.id
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["name"] == "ash-deployment"
    end
  end

  describe "show" do
    test "returns a deployment group by id", %{conn: conn, deployment_group: dg} do
      conn = get(conn, "/api/v2/deployment-groups/#{dg.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["name"] == dg.name
    end
  end

  describe "update" do
    test "updates a deployment group", %{conn: conn, deployment_group: dg} do
      conn =
        patch(conn, "/api/v2/deployment-groups/#{dg.id}", %{
          "data" => %{
            "type" => "deployment-group",
            "id" => "#{dg.id}",
            "attributes" => %{
              "is_active" => true
            }
          }
        })

      resp = json_response(conn, 200)
      assert resp["data"]["attributes"]["is_active"] == true
    end
  end

  describe "list_by_product" do
    test "lists deployment groups by product", %{conn: conn, product: product, deployment_group: dg} do
      conn = get(conn, "/api/v2/deployment-groups/by-product/#{product.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      names = Enum.map(resp["data"], & &1["attributes"]["name"])
      assert dg.name in names
    end
  end

  describe "get_by_product_and_name" do
    test "returns a deployment group by product and name", %{conn: conn, product: product, deployment_group: dg} do
      conn = get(conn, "/api/v2/deployment-groups/by-product/#{product.id}/by-name/#{dg.name}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["name"] == dg.name
    end
  end

  describe "delete" do
    test "deletes a deployment group", %{conn: conn, deployment_group: dg} do
      conn = delete(conn, "/api/v2/deployment-groups/#{dg.id}")
      assert response(conn, 200)
    end
  end
end
