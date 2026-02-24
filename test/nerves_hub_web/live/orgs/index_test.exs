defmodule NervesHubWeb.Live.Orgs.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  describe "onboarding" do
    test "provides a simple way for users to create their first organization and product" do
      user = Fixtures.user_fixture(%{name: "Waffles"})

      token = NervesHub.Accounts.create_user_session_token(user)

      build_conn()
      |> init_test_session(%{
        "user_token" => token
      })
      |> visit(~p"/orgs")
      |> assert_has("p", text: "Create your first organization and product to start managing devices.")
      |> fill_in("Organization name", with: "Doggos", exact: false)
      |> fill_in("Product name", with: "Ball", exact: false)
      |> click_button("Create & Get Started")
      |> assert_path("/org/Doggos/Ball/devices")
    end

    test "shows a friendly message if there was problems submitting the onboarding form" do
      user = Fixtures.user_fixture(%{name: "Waffles"})

      token = NervesHub.Accounts.create_user_session_token(user)

      build_conn()
      |> init_test_session(%{
        "user_token" => token
      })
      |> visit(~p"/orgs")
      |> assert_has("p", text: "Create your first organization and product to start managing devices.")
      |> fill_in("Organization name", with: "", exact: false)
      |> fill_in("Product name", with: "", exact: false)
      |> click_button("Create & Get Started")
      |> assert_path("/orgs")
      |> assert_has("div", text: "name can't be blank")
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
