defmodule NervesHubWeb.Live.LayoutTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  test "the header's user menu names the user and links to their account", %{conn: conn, user: user} do
    conn
    |> visit("/orgs")
    |> assert_has("#user-menu", text: user.email)
    |> assert_has("#user-menu a[href='/account/tokens']", text: "Access tokens")
  end

  test "can logout", %{conn: conn} do
    conn
    |> visit("/")
    |> click_link("Log out")
    |> assert_path("/login")
  end
end
