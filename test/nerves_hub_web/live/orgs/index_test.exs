defmodule NervesHubWeb.Live.Orgs.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Devices.Connections
  alias NervesHub.Fixtures

  test "user is redirected to login when trying to list their orgs, but the user isn't logged in" do
    build_conn()
    |> visit("/orgs")
    |> assert_path("/login")
    |> assert_has("div", text: "You must login to access this page.")
  end

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
    test "all orgs listed with connected and disconnected device counts", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      _ = Fixtures.device_fixture(org, product, firmware)
      _ = Fixtures.device_fixture(org, product, firmware)

      device = Fixtures.device_fixture(org, product, firmware)
      {:ok, device_connection} = Connections.device_connecting(device)
      Connections.device_connected(device, device_connection.id)

      conn
      |> visit("/orgs")
      |> assert_has("h1", text: "Organizations")
      |> assert_has("h3", text: org.name)
      |> assert_has("span#org-connected-devices-count", text: "1")
      |> assert_has("span#org-disconnected-devices-count", text: "3")
      |> assert_has("span.product-connected-devices-count", text: "1")
      |> assert_has("span.product-disconnected-devices-count", text: "3")
    end
  end
end
