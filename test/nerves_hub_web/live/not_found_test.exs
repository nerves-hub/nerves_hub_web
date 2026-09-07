defmodule NervesHubWeb.Live.NotFoundTest do
  @moduledoc """
  The 404 page is reached from two directions: a bang lookup raising
  `Ecto.NoResultsError`, which `phoenix_ecto` maps to 404, and an explicit
  `NervesHubWeb.NotFoundError`. Neither is visible at the call site of the page
  that depends on it, so these assert the status rather than the exception —
  swapping one mechanism for the other should not break them, but losing the
  404 should.
  """

  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  describe "an org or product that does not exist" do
    test "unknown org", %{conn: conn} do
      assert_error_sent(404, fn -> get(conn, ~p"/org/nope") end)
    end

    test "unknown product", %{conn: conn, org: org} do
      assert_error_sent(404, fn -> get(conn, ~p"/org/#{org}/nope/devices") end)
    end

    test "an org the user is not a member of", %{conn: conn} do
      other_user = Fixtures.user_fixture(%{name: "Somebody Else"})
      other_org = Fixtures.org_fixture(other_user, %{name: "SomebodyElseCorp"})

      assert_error_sent(404, fn -> get(conn, ~p"/org/#{other_org}") end)
    end

    test "a product belonging to another org", %{conn: conn, org: org} do
      other_user = Fixtures.user_fixture(%{name: "Somebody Else"})
      other_org = Fixtures.org_fixture(other_user, %{name: "SomebodyElseCorp"})
      other_product = Fixtures.product_fixture(other_user, other_org, %{name: "Theirs"})

      # Asked for under an org the user *can* see, so this is the scoping in
      # Products.get_by_name!/2 doing the work rather than the org lookup.
      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{other_product.name}/devices")
      end)
    end
  end

  describe "a record that does not exist" do
    test "unknown device", %{conn: conn, org: org, product: product} do
      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{product}/devices/nope")
      end)
    end

    test "unknown firmware", %{conn: conn, org: org, product: product} do
      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{product}/firmware/#{Ecto.UUID.generate()}")
      end)
    end

    test "unknown archive", %{conn: conn, org: org, product: product} do
      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{product}/archives/#{Ecto.UUID.generate()}")
      end)
    end

    test "unknown deployment group", %{conn: conn, org: org, product: product} do
      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{product}/deployment_groups/nope")
      end)
    end

    test "unknown support script", %{conn: conn, org: org, product: product} do
      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{product}/scripts/999999999/edit")
      end)
    end

    test "unknown org user", %{conn: conn, org: org} do
      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/settings/users/999999999/edit")
      end)
    end
  end

  describe "a record belonging to another product" do
    setup %{user: user, org: org} do
      %{other_product: Fixtures.product_fixture(user, org, %{name: "Another"})}
    end

    test "device", %{conn: conn, org: org, other_product: other_product, device: device} do
      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{other_product}/devices/#{device.identifier}")
      end)
    end

    test "device, on a route guarded by Plugs.Device", %{
      conn: conn,
      org: org,
      other_product: other_product,
      device: device
    } do
      # This one renders the 404 itself rather than raising, so there is no
      # error to assert on — only the response.
      conn = get(conn, ~p"/org/#{org}/#{other_product}/devices/#{device.identifier}/audit_logs/download")

      assert conn.status == 404
    end

    test "firmware", %{conn: conn, org: org, other_product: other_product, firmware: firmware} do
      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{other_product}/firmware/#{firmware.uuid}")
      end)
    end

    test "deployment group", %{
      conn: conn,
      org: org,
      other_product: other_product,
      deployment_group: deployment_group
    } do
      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{other_product}/deployment_groups/#{deployment_group.name}")
      end)
    end
  end

  test "a path that matches no route at all", %{conn: conn} do
    # Unlike the lookups above, this one never raises: the router's own
    # NoRouteError is turned into a response before the test process sees it.
    # Asserting the body as well as the status is what proves the branded page
    # is served rather than Plug's bare "Not Found".
    conn = get(conn, "/this/does/not/exist")

    assert conn.status == 404
    assert conn.resp_body =~ "Sorry, the page you are looking can't be found."
  end
end
