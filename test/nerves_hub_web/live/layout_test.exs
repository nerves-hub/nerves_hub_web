defmodule NervesHubWeb.Live.LayoutTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  test "can logout", %{conn: conn} do
    conn
    |> visit("/orgs")
    |> click_link("Logout")
    |> assert_path("/login")
  end
end
