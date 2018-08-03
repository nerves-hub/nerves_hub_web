defmodule NervesHubWWWWeb.TenantKeyControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser

  alias NervesHubCore.Fixtures

  @create_attrs %{name: "tenant's key", key: "foo"}
  @update_attrs %{name: "new tenant's key", key: "bar"}
  @invalid_attrs %{name: nil}

  describe "index" do
    test "lists all tenant_keys", %{conn: conn} do
      conn = get(conn, tenant_key_path(conn, :index))
      assert html_response(conn, 200) =~ "Listing Tenant keys"
    end
  end

  describe "new tenant_keys" do
    test "renders form", %{conn: conn} do
      conn = get(conn, tenant_key_path(conn, :new))
      assert html_response(conn, 200) =~ "New Tenant keys"
    end
  end

  describe "create tenant_keys" do
    test "redirects to show when data is valid", %{conn: conn, current_tenant: tenant} do
      params = %{name: "foobarbazbangpow", key: "a key"}
      conn = post(conn, tenant_key_path(conn, :create), tenant_key: params)

      assert redirected_to(conn) == tenant_path(conn, :edit, tenant)

      conn = get(conn, tenant_path(conn, :edit, tenant))
      assert html_response(conn, 200) =~ params.name
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, tenant_key_path(conn, :create), tenant_key: @invalid_attrs)
      assert html_response(conn, 200) =~ "New Tenant keys"
    end
  end

  describe "edit tenant_keys" do
    test "renders form for editing chosen tenant_keys", %{conn: conn, current_tenant: tenant} do
      tenant_key = Fixtures.tenant_key_fixture(tenant, @create_attrs)
      conn = get(conn, tenant_key_path(conn, :edit, tenant_key))
      assert html_response(conn, 200) =~ "Edit Tenant Key"
    end
  end

  describe "update tenant_key" do
    test "redirects when data is valid", %{conn: conn, current_tenant: tenant} do
      tenant_key = Fixtures.tenant_key_fixture(tenant, @create_attrs)
      conn = put(conn, tenant_key_path(conn, :update, tenant_key), tenant_key: @update_attrs)

      assert redirected_to(conn) == tenant_path(conn, :edit, tenant)

      conn = get(conn, tenant_key_path(conn, :show, tenant_key))
      assert html_response(conn, 200)
    end

    test "renders errors when data is invalid", %{conn: conn, current_tenant: tenant} do
      tenant_key = Fixtures.tenant_key_fixture(tenant, @create_attrs)

      conn =
        put(
          conn,
          tenant_key_path(conn, :update, tenant_key),
          tenant_key: @invalid_attrs
        )

      assert html_response(conn, 200) =~ "Edit Tenant Key"
    end
  end

  describe "delete tenant_key" do
    test "deletes chosen tenant_key", %{conn: conn, current_tenant: tenant} do
      tenant_key = Fixtures.tenant_key_fixture(tenant, @create_attrs)

      conn = delete(conn, tenant_key_path(conn, :delete, tenant_key))
      assert redirected_to(conn) == tenant_path(conn, :edit, tenant)

      assert_error_sent(404, fn ->
        get(conn, tenant_key_path(conn, :show, tenant_key))
      end)
    end
  end
end
