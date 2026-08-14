defmodule NervesHubWeb.Live.Org.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  test "shows empty state when org has no products" do
    user = Fixtures.user_fixture(%{email: "empty_org_user@test.com"})
    org = Fixtures.org_fixture(user, %{name: "EmptyOrg"})
    token = NervesHub.Accounts.create_user_session_token(user)

    build_conn()
    |> init_test_session(%{"user_token" => token})
    |> visit("/org/#{org.name}")
    |> assert_has("h2", text: "#{org.name} doesn't have any products yet")
  end

  test "lists products when org has products", %{conn: conn, org: org, user: user} do
    product = Fixtures.product_fixture(user, org)

    conn
    |> visit("/org/#{org.name}")
    |> assert_has("h1", text: "Products")
    |> assert_has("a", text: product.name)
  end
end
