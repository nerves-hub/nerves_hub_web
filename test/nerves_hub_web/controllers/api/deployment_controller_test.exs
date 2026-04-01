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

    test "includes device_count, releases_count, and current_release", %{
      conn: conn,
      org: org,
      product: product,
      user: user,
      tmp_dir: tmp_dir
    } do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      Fixtures.deployment_group_fixture(firmware, %{user: user})

      conn = get(conn, Routes.api_deployment_group_path(conn, :index, org.name, product.name))
      [deployment_group] = json_response(conn, 200)["data"]

      assert deployment_group["device_count"] == 0
      assert deployment_group["releases_count"] >= 1
      assert deployment_group["firmware_uuid"] == firmware.uuid

      current_release = deployment_group["current_release"]
      assert current_release["number"] >= 1
      assert current_release["inserted_at"]
      assert current_release["updated_at"]

      release_firmware = current_release["firmware"]
      assert release_firmware["uuid"] == firmware.uuid
      assert release_firmware["version"] == firmware.version
      assert release_firmware["architecture"] == firmware.architecture
      assert release_firmware["platform"] == firmware.platform
    end
  end

  describe "show deployment group" do
    setup [:create_deployment_group]

    test "returns deployment group with all fields", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      path =
        Routes.api_deployment_group_path(
          conn,
          :show,
          org.name,
          product.name,
          deployment_group.name
        )

      conn = get(conn, path)
      data = json_response(conn, 200)["data"]

      assert data["name"] == deployment_group.name
      assert data["device_count"] == 0
      assert data["releases_count"] >= 1
      assert is_boolean(data["is_active"])
      assert data["state"] in ["on", "off"]
      assert is_boolean(data["delta_updatable"])

      assert %{"version" => _, "tags" => _} = data["conditions"]

      current_release = data["current_release"]
      assert current_release["number"] >= 1
      assert current_release["firmware"]["uuid"]
    end

    test "includes device_count reflecting assigned devices", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group,
      firmware: firmware
    } do
      _device = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})

      path =
        Routes.api_deployment_group_path(
          conn,
          :show,
          org.name,
          product.name,
          deployment_group.name
        )

      conn = get(conn, path)
      data = json_response(conn, 200)["data"]

      assert data["device_count"] == 1
    end
  end

  describe "create deployment group" do
    setup context do
      org_key = Fixtures.org_key_fixture(context.org, context.user, context.tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, context.product, %{dir: context.tmp_dir})

      params = %{
        name: "test",
        org_id: context.org.id,
        firmware: firmware.uuid,
        firmware_id: firmware.id,
        product_id: firmware.product_id,
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
      assert json_response(conn, 422)["errors"] != %{}
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

    test "can change firmware_id to release new firmware", %{
      conn: conn,
      deployment_group: deployment_group,
      org: org,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      path =
        Routes.api_deployment_group_path(
          conn,
          :update,
          org.name,
          product.name,
          deployment_group.name
        )

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1", dir: tmp_dir})

      conn = put(conn, path, deployment: %{"firmware_id" => new_firmware.id})
      assert json_response(conn, 200)["data"]["firmware_uuid"] == new_firmware.uuid

      path =
        Routes.api_deployment_group_path(
          conn,
          :show,
          org.name,
          product.name,
          deployment_group.name
        )

      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["firmware_uuid"] == new_firmware.uuid
    end

    test "when changing the archive id, the firmware id is also required", %{
      conn: conn,
      deployment_group: deployment_group,
      org: org,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      path =
        Routes.api_deployment_group_path(
          conn,
          :update,
          org.name,
          product.name,
          deployment_group.name
        )

      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn = put(conn, path, deployment: %{"archive_id" => archive.id})
      assert json_response(conn, 422)["errors"]["firmware"] == ["can't be blank"]

      path =
        Routes.api_deployment_group_path(
          conn,
          :show,
          org.name,
          product.name,
          deployment_group.name
        )

      conn = get(conn, path)

      assert json_response(conn, 200)["data"]["firmware_uuid"] ==
               deployment_group.current_release.firmware.uuid

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1", dir: tmp_dir})

      conn = put(conn, path, deployment: %{"firmware_id" => new_firmware.id, "archive_id" => archive.id})
      assert json_response(conn, 200)["data"]["firmware_uuid"] == new_firmware.uuid
      assert json_response(conn, 200)["data"]["archive_uuid"] == archive.uuid

      path =
        Routes.api_deployment_group_path(
          conn,
          :show,
          org.name,
          product.name,
          deployment_group.name
        )

      conn = get(conn, path)

      assert json_response(conn, 200)["data"]["firmware_uuid"] ==
               new_firmware.uuid

      assert json_response(conn, 200)["data"]["archive_uuid"] ==
               archive.uuid
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

      [audit_log | _] = AuditLogs.logs_for(deployment_group)
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

  defp create_deployment_group(%{user: user, org: org, product: product, tmp_dir: tmp_dir}) do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
    {:ok, %{deployment_group: deployment_group, org_key: org_key, firmware: firmware}}
  end
end
