defmodule NervesHubWeb.RoleValidateHelpersTest do
  use NervesHub.DataCase, async: true

  import Plug.Test
  import Plug.Conn

  alias NervesHub.Fixtures
  alias NervesHubWeb.Helpers.RoleValidateHelpers, as: Validator

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    conn =
      conn(:get, "/")
      |> assign(:user, user)
      |> assign(:org, org)
      |> assign(:product, product)

    %{conn: conn, org: org, product: product, user: user}
  end

  test "org creator has admin role", %{conn: conn} do
    refute Validator.validate_role(conn, org: :admin).halted
  end

  test "org role", %{conn: conn} do
    user = Fixtures.user_fixture()

    assert_raise(NervesHubWeb.UnauthorizedError, fn ->
      conn
      |> Plug.Conn.assign(:user, user)
      |> Validator.validate_role(org: :admin)
    end)
  end
end
