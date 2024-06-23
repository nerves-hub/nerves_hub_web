defmodule NervesHubWeb.Live.Orgs.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  #
  # this is a UI/UX we should take into account
  #
  # describe "no org memberships" do
  #   test "no orgs listed", %{conn: conn, org: org, user: user} do
  #     {:ok, view, html} = live(conn, ~p"/orgs")

  #     assert html =~ "<h1 class=\"mt-2\">My Organizations</h1>"
  #     assert html =~ "<h3>#{user.name}</h3>"
  #     assert html =~ "<h3>#{org.name}</h3>"
  #   end
  # end

  describe "has orgs memberships" do
    test "all orgs listed", %{conn: conn, org: org, user: user} do
      conn
      |> visit("/orgs")
      |> assert_has("h1", text: "My Organizations")
      |> assert_has("h3", text: user.username)
      |> assert_has("h3", text: org.name)
    end
  end
end
