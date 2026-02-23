defmodule NervesHubWeb.Live.Orgs.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  describe "no org memberships" do
    test "shows onboarding form" do
      user = NervesHub.Fixtures.user_fixture()

      token = NervesHub.Accounts.create_user_session_token(user)

      build_conn()
      |> init_test_session(%{"user_token" => token})
      |> visit("/orgs")
      |> assert_has("h1", text: "Get Started")
      |> assert_has("button", text: "Create & Get Started")
    end
  end

  describe "has orgs memberships" do
    test "all orgs listed", %{conn: conn, org: org} do
      conn
      |> visit("/orgs")
      |> assert_has("h1", text: "Organizations")
      |> assert_has("h3", text: org.name)
    end
  end
end
