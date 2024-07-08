defmodule NervesHubWeb.Live.Orgs.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  describe "no org memberships" do
    test "no orgs listed" do
      user = NervesHub.Fixtures.user_fixture()

      build_conn()
      |> init_test_session(%{"auth_user_id" => user.id})
      |> visit("/orgs")
      |> assert_has("h3", text: "You aren't a member of any organizations.")
    end
  end

  describe "has orgs memberships" do
    test "all orgs listed", %{conn: conn, org: org} do
      conn
      |> visit("/orgs")
      |> assert_has("h1", text: "My Organizations")
      |> assert_has("h3", text: org.name)
    end
  end
end
