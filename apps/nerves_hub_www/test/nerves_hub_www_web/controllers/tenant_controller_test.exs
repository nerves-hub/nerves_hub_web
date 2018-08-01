defmodule NervesHubWWWWeb.TenantControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser

  alias NervesHubCore.Fixtures

  describe "edit tenant" do
    test "renders form for editing tenant on conn", %{conn: conn, current_tenant: tenant} do
      conn = get(conn, tenant_path(conn, :edit, tenant))
      assert html_response(conn, 200) =~ "Tenant Settings"
    end

    test "does not render form for tenant not on conn", %{conn: conn, current_tenant: _tenant} do
      new_tenant = Fixtures.tenant_fixture(%{name: "Secret Tenant Name"})
      conn = get(conn, tenant_path(conn, :edit, new_tenant))
      refute html_response(conn, 200) =~ "Secret Tenant Name"
    end
  end

  describe "update tenant" do
    test "cannot update wrong tenant", %{conn: conn, current_tenant: tenant} do
      new_tenant = Fixtures.tenant_fixture(%{name: "Secret Tenant Name"})
      user = Fixtures.user_fixture(new_tenant, %{email: "new@tenant.com"})

      conn = put(conn, tenant_path(conn, :update, new_tenant), tenant: %{name: "Nefarious Name"})

      assert redirected_to(conn) == tenant_path(conn, :edit, tenant)

      new_conn =
        build_conn()
        |> Map.put(:assigns, %{tenant: new_tenant})
        |> init_test_session(%{"auth_user_id" => user.id})

      updated_conn = get(new_conn, tenant_path(conn, :edit, new_tenant))

      refute html_response(updated_conn, 200) =~ "Nefarious Name"
    end

    test "redirects when data is valid", %{conn: conn, current_tenant: tenant} do
      conn = put(conn, tenant_path(conn, :update, tenant), tenant: %{name: "new name"})

      assert redirected_to(conn) == tenant_path(conn, :edit, tenant)
    end

    test "renders errors when data is invalid", %{conn: conn, current_tenant: tenant} do
      conn =
        put(
          conn,
          tenant_path(conn, :update, tenant),
          tenant: %{name: ""}
        )

      assert html_response(conn, 200) =~ "Tenant Settings"
      assert html_response(conn, 200) =~ "be blank"
    end
  end
end
