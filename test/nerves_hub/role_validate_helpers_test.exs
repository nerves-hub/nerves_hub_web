defmodule NervesHub.RoleValidateHelpersTest do
  use NervesHub.DataCase, async: true
  use Plug.Test

  alias NervesHub.Fixtures
  alias NervesHub.RoleValidateHelpers, as: Validator

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    conn =
      conn(:get, "/")
      |> assign(:user, user)
      |> assign(:org, org)
      |> assign(:product, product)

    %{conn: conn, user: user, org: org, product: product}
  end

  test "org creator has admin role", %{conn: conn} do
    refute Validator.validate_role(conn, org: :admin).halted
  end

  test "org role", %{conn: conn} do
    user = Fixtures.user_fixture()

    conn =
      conn
      |> Plug.Conn.assign(:user, user)
      |> Validator.validate_role(org: :admin)

    assert conn.halted
  end
end
