defmodule NervesHubWeb.Live.ManagedDeployments.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  test "no deployments", %{conn: conn, user: user, org: org} do
    product = Fixtures.product_fixture(user, org, %{name: "Spaghetti"})

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
    |> assert_has("h3", text: "#{product.name} doesn’t have any deployments configured")
  end

  test "has deployments", %{conn: conn, org: org, product: product, deployment: deployment} do
    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
    |> assert_has("h1", text: "Deployments")
    |> assert_has("a", text: deployment.name)
  end
end
