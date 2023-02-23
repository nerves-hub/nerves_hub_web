defmodule NervesHub.RoleValidateHelpersTest do
  use NervesHub.DataCase, async: true
  use Plug.Test

  alias NervesHub.Fixtures
  alias NervesHub.Accounts
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

  test "product creator has admin role", %{conn: conn} do
    refute Validator.validate_role(conn, product: :admin).halted
  end

  test "product role", %{conn: conn} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user, %{name: "product-role-test"})
    product = Fixtures.product_fixture(user, org)

    conn =
      conn
      |> Plug.Conn.assign(:product, product)
      |> Validator.validate_role(product: :admin)

    assert conn.halted
  end

  test "check account role before product role", %{conn: conn, org: org} do
    user = Fixtures.user_fixture()
    Accounts.add_org_user(org, user, %{role: :admin})

    conn =
      conn
      |> Plug.Conn.assign(:user, user)
      |> Validator.validate_role(product: :admin)

    refute conn.halted
  end
end
