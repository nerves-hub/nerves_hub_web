defmodule NervesHubWeb.Live.LayoutTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  test "can logout", %{conn: conn} do
    conn
    |> visit("/")
    |> click_link("Log out")
    |> assert_path("/login")
  end
end
