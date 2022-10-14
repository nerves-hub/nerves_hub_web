defmodule NervesHubWWWWeb.DeploymentControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.{AuditLogs, Deployments, Deployments.Deployment, Fixtures}

  describe "index" do
    test "lists all deployments", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      conn = get(conn, Routes.deployment_path(conn, :index, org.name, product.name))
      assert html_response(conn, 200) =~ "Deployments"
    end
  end

  describe "new deployment" do
    test "renders form with valid request params", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      conn =
        get(
          conn,
          Routes.deployment_path(conn, :new, org.name, product.name),
          deployment: %{firmware_id: firmware.id}
        )

      assert html_response(conn, 200) =~ "Create Deployment"

      assert html_response(conn, 200) =~
               Routes.deployment_path(conn, :create, org.name, product.name)
    end

    test "redirects with invalid firmware", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      conn =
        get(conn, Routes.deployment_path(conn, :new, org.name, product.name),
          deployment: %{firmware_id: -1}
        )

      assert redirected_to(conn, 302) =~
               Routes.deployment_path(conn, :new, org.name, product.name)
    end

    test "renders create deployment when no firmware_id is passed", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)
      Fixtures.firmware_fixture(org_key, product)
      conn = get(conn, Routes.deployment_path(conn, :new, org.name, product.name))

      assert html_response(conn, 200) =~ "Add Deployment"

      assert html_response(conn, 200) =~
               Routes.deployment_path(conn, :create, org.name, product.name)
    end

    test "redirects to firmware upload firmware_id is passed and no firmwares are found" do
      user = Fixtures.user_fixture(%{email: "new@org.com"})
      org = Fixtures.org_fixture(user, %{name: "empty_org"})
      product = Fixtures.product_fixture(user, org)

      conn =
        build_conn()
        |> Map.put(:assigns, %{org: org})
        |> init_test_session(%{"auth_user_id" => user.id})

      conn = get(conn, Routes.deployment_path(conn, :new, org.name, product.name))

      assert redirected_to(conn, 302) =~
               Routes.firmware_path(conn, :upload, org.name, product.name)
    end
  end

  describe "create deployment" do
    test "redirects to index when data is valid", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)

      firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "relatively unusual version"
        })

      deployment_params = %{
        firmware_id: firmware.id,
        org_id: org.id,
        name: "Test Deployment ABC",
        tags: "beta, beta-edge",
        version: "< 1.0.0",
        is_active: true,
        delta_updatable: true
      }

      # check that we end up in the right place
      create_conn =
        post(
          conn,
          Routes.deployment_path(conn, :create, org.name, product.name),
          deployment: deployment_params
        )

      assert redirected_to(create_conn, 302) =~
               Routes.deployment_path(create_conn, :index, org.name, product.name)

      # check that the proper creation side effects took place
      route = Routes.deployment_path(conn, :show, org.name, product.name, deployment_params.name)
      conn = get(conn, route)

      assert html_response(conn, 200) =~ deployment_params.name
      assert html_response(conn, 200) =~ "Off"
      assert html_response(conn, 200) =~ firmware.version
      assert html_response(conn, 200) =~ "Delta firmware updates enabled"
    end

    test "audits on success", %{conn: conn, org: org, fixture: fixture} do
      %{firmware: firmware, product: product} = fixture

      deployment_params = %{
        firmware_id: firmware.id,
        org_id: org.id,
        name: "Test Deployment ABC",
        tags: "beta, beta-edge",
        version: "< 1.0.0"
      }

      create_conn =
        post(
          conn,
          Routes.deployment_path(conn, :create, org.name, product.name),
          deployment: deployment_params
        )

      redirect_path = Routes.deployment_path(create_conn, :index, org.name, product.name)

      assert redirected_to(create_conn, 302) =~ redirect_path

      conn = get(create_conn, redirect_path)
      assert get_flash(conn, :info) == "Deployment created"

      [%{resource_type: resource_type, params: params}] = AuditLogs.logs_by(fixture.user)
      assert resource_type == Deployment
      assert params["firmware_id"] == deployment_params.firmware_id
      assert params["org_id"] == deployment_params.org_id
      assert params["name"] == deployment_params.name
    end
  end

  describe "edit deployment" do
    test "edits the chosen resource", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)
      firmware = Fixtures.firmware_fixture(org_key, product)
      deployment = Fixtures.deployment_fixture(org, firmware)

      conn =
        get(conn, Routes.deployment_path(conn, :edit, org.name, product.name, deployment.name))

      assert html_response(conn, 200) =~ "Edit"

      assert html_response(conn, 200) =~
               Routes.deployment_path(conn, :update, org.name, product.name, deployment.name)
    end
  end

  describe "update deployment" do
    test "update the chosen resource", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)
      firmware = Fixtures.firmware_fixture(org_key, product)
      deployment = Fixtures.deployment_fixture(org, firmware)

      conn =
        put(
          conn,
          Routes.deployment_path(conn, :update, org.name, product.name, deployment.name),
          deployment: %{
            "version" => "4.3.2",
            "tags" => "new, tags, now",
            "name" => "not original",
            "firmware_id" => firmware.id,
            "delta_updatable" => false
          }
        )

      {:ok, reloaded_deployment} = Deployments.get_deployment(product, deployment.id)

      assert redirected_to(conn, 302) =~
               Routes.deployment_path(
                 conn,
                 :show,
                 org.name,
                 product.name,
                 reloaded_deployment.name
               )

      assert reloaded_deployment.name == "not original"
      assert reloaded_deployment.conditions["version"] == "4.3.2"
      assert Enum.sort(reloaded_deployment.conditions["tags"]) == Enum.sort(~w(new tags now))
      assert reloaded_deployment.delta_updatable == false
    end

    test "failed update shows errors", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)
      firmware = Fixtures.firmware_fixture(org_key, product)
      deployment = Fixtures.deployment_fixture(org, firmware)

      conn =
        put(conn, Routes.deployment_path(conn, :update, org.name, product.name, deployment.name),
          deployment: %{"tags" => "", "version" => ""}
        )

      assert response(conn, 200) =~ "should have at least 1 item(s)"
    end

    test "audits on success", %{conn: conn, fixture: fixture} do
      %{org: org, deployment: deployment, product: product} = fixture

      params = %{"tags" => "new_tag", "version" => "> 0.1.0"}

      update_conn =
        put(
          conn,
          Routes.deployment_path(conn, :update, org.name, product.name, deployment.name),
          deployment: params
        )

      redirect_path = Routes.deployment_path(update_conn, :index, org.name, product.name)

      assert redirected_to(update_conn, 302) =~ redirect_path

      conn = get(update_conn, redirect_path)
      assert get_flash(conn, :info) == "Deployment updated"

      [audit_log] = AuditLogs.logs_for(deployment)

      assert audit_log.resource_type == Deployment
      assert Map.has_key?(audit_log.changes, "conditions")
    end
  end

  describe "delete deployment" do
    test "deletes chosen resource", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)
      firmware = Fixtures.firmware_fixture(org_key, product)
      deployment = Fixtures.deployment_fixture(org, firmware)

      conn =
        delete(
          conn,
          Routes.deployment_path(conn, :delete, org.name, product.name, deployment.name)
        )

      assert redirected_to(conn) == Routes.deployment_path(conn, :index, org.name, product.name)
      assert Deployments.get_deployment(product, deployment.id) == {:error, :not_found}
    end
  end
end
