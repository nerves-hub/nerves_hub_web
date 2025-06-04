defmodule NervesHubWeb.Live.NewUI.DeploymentGroups.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Repo

  setup %{conn: conn} do
    [conn: init_test_session(conn, %{"new_ui" => true})]
  end

  test "can update queue management", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    assert deployment_group.queue_management == :FIFO

    conn
    |> visit(
      "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/settings"
    )
    |> select("Queue management", option: "LIFO")
    |> submit()

    assert Repo.reload(deployment_group).queue_management == :LIFO
  end
end
