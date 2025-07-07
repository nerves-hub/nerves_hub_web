defmodule NervesHubWeb.Live.NewUi.LayoutTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Swoosh.TestAssertions

  alias NervesHub.Accounts

  setup context do
    conn = init_test_session(context.conn, %{"new_ui" => true})
    %{context | conn: conn}
  end

  test "can logout", %{conn: conn, user: user} do
    conn
    |> visit("/orgs")
    |> click_link("Log out")
    |> assert_path("/login")
  end
end
