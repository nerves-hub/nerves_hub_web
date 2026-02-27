defmodule NervesHubWeb.Live.DeploymentGroups.Show.ReleasesTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Repo

  setup context do
    %{
      org: org,
      product: product,
      deployment_group: deployment_group
    } = context

    conn =
      context.conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
      |> assert_has("div", text: "Release History")

    %{context | conn: conn}
  end

  test "shows a nice message when there are no releases", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    Repo.delete_all(DeploymentRelease)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
    |> assert_has("div", text: "No releases have been created.")
  end

  test "shows created releases", %{conn: conn} do
    conn
    |> assert_has("th", text: "Released")
    |> assert_has("th", text: "Firmware Version")
    |> assert_has("td", text: "1.0.0")
  end
end
