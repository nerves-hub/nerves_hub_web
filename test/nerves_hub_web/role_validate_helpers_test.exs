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
