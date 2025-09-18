defmodule NervesHubWeb.Live.NewUI.DeploymentGroups.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Repo

  setup context do
    conn =
      context.conn
      |> put_session("new_ui", true)
      |> visit(
        "/org/#{context.org.name}/#{context.product.name}/deployment_groups/#{context.deployment_group.name}/settings"
      )
      |> assert_has("div", text: "General settings")

    %{context | conn: conn}
  end

  test "can update queue management", %{
    conn: conn,
    deployment_group: deployment_group
  } do
    assert deployment_group.queue_management == :FIFO

    conn
    |> select("Queue management", option: "LIFO")
    |> submit()

    assert Repo.reload(deployment_group).queue_management == :LIFO
  end

  test "can update only version", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("Version requirement", with: "1.2.3")
    |> submit()

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.conditions["version"] == "1.2.3"
  end

  test "can update only tags", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("Tag(s) distributed to", with: "a, b")
    |> submit()

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.conditions["tags"] == ["a", "b"]
  end

  test "can update tags and version", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("Tag(s) distributed to", with: "a, b")
    |> fill_in("Version requirement", with: "1.2.3")
    |> submit()

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.conditions["tags"] == ["a", "b"]
    assert deployment_group.conditions["version"] == "1.2.3"
  end
end
