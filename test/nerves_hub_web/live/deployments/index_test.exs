defmodule NervesHubWeb.Live.Deployments.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  test "no deployments", %{conn: conn, user: user, org: org} do
    product = Fixtures.product_fixture(user, org, %{name: "Spaghetti"})

    conn
    |> visit("/products/#{hashid(product)}/deployments")
    |> assert_has("h3", text: "#{product.name} doesn’t have any deployments configured")
  end

  test "has deployments", %{conn: conn, product: product, deployment: deployment} do
    conn
    |> visit("/products/#{hashid(product)}/deployments")
    |> assert_has("h1", text: "Deployments")
    |> assert_has("a", text: deployment.name)
  end
end
