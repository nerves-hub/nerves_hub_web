defmodule NervesHubWeb.RoleValidateHelpersTest do
  use NervesHub.DataCase, async: true

  import Plug.Conn
  import Plug.Test

  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHubWeb.Helpers.RoleValidateHelpers, as: Validator

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    scope =
      Scope.for_user(user)
      |> Scope.put_org(org)

    conn =
      conn(:get, "/")
      |> assign(:current_scope, scope)
      |> assign(:product, product)

    %{conn: conn, user: user, org: org, product: product}
  end

  test "org creator has admin role", %{conn: conn} do
    refute Validator.validate_role(conn, org: :admin).halted
  end

  @tag :tmp_dir
  test "validates role using device's org when device is in scope", %{tmp_dir: tmp_dir, user: user} do
    org = Fixtures.org_fixture(user)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware) |> NervesHub.Repo.preload(:org)

    scope = Scope.for_user(user)

    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Conn.assign(:current_scope, scope)
      |> Plug.Conn.assign(:device, device)

    refute Validator.validate_role(conn, org: :view).halted
  end

  test "raises when scope has no org and no device" do
    user = Fixtures.user_fixture()
    scope = Scope.for_user(user)

    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Conn.assign(:current_scope, scope)

    assert_raise(NervesHubWeb.UnauthorizedError, fn ->
      Validator.validate_role(conn, org: :admin)
    end)
  end

  test "org role", %{conn: conn} do
    user = Fixtures.user_fixture()

    assert_raise(NervesHubWeb.UnauthorizedError, fn ->
      scope = Scope.for_user(user)

      conn
      |> Plug.Conn.assign(:current_scope, scope)
      |> Validator.validate_role(org: :admin)
    end)
  end
end
