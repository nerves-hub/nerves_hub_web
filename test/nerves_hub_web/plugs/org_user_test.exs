defmodule NervesHubWeb.Plugs.OrgUserTest do
  use NervesHubWeb.ConnCase.Browser, async: true
  use Plug.Test

  alias NervesHub.{Accounts, Fixtures}

  setup context do
    {:ok, org_user} = Accounts.get_org_user(context.org, context.user)
    Map.put(context, :org_user, org_user)
  end

  test "org_user is set when found", %{conn: conn, org_user: org_user} do
    conn =
      conn
      |> Map.put(:params, %{"user_id" => org_user.user_id})
      |> NervesHubWeb.Plugs.OrgUser.call([])

    assert conn.assigns.org_user == org_user
  end

  test "404 is rendered user is not found", %{conn: conn} do
    conn =
      conn
      |> Map.put(:params, %{"user_id" => 000})
      |> NervesHubWeb.Plugs.OrgUser.call([])

    assert html_response(conn, 404) =~ "Sorry, the page you are looking for does not exist."
  end

  test "404 is rendered when org_user is not found", %{conn: conn, user: user} do
    user2 = Fixtures.user_fixture(%{username: user.username <> "0"})

    conn =
      conn
      |> Map.put(:params, %{"user_id" => user2.id})
      |> NervesHubWeb.Plugs.OrgUser.call([])

    assert html_response(conn, 404) =~ "Sorry, the page you are looking for does not exist."
  end
end
