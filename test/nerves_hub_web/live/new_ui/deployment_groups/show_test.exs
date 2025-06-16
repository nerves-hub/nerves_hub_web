defmodule NervesHubWeb.Live.NewUI.DelploymentGroups.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Repo

  describe "settings" do
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

    test "toggle delta updates", %{conn: conn, deployment_group: deployment_group} do
      # Delta updates are enabled in deployment group fixture
      assert deployment_group.delta_updatable

      conn
      |> check("Delta updates")
      |> assert_has("div", text: "Delta updates disabled successfully.")

      deployment_group = Repo.reload(deployment_group)
      refute deployment_group.delta_updatable
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
end
