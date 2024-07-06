defmodule NervesHubWeb.Live.Orgs.NewTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  describe "new org" do
    test "requires a name", %{conn: conn} do
      conn
      |> visit("/orgs/new")
      |> assert_has("h1", text: "Create New Organization")
      |> click_button("Create Organization")
      |> assert_path("/orgs/new")
      |> assert_has("p", text: "Oops, something went wrong! Please check the errors below.")
      |> assert_has(".help-block", text: "can't be blank")
    end

    test "requires a name with no spaces", %{conn: conn} do
      conn
      |> visit("/orgs/new")
      |> assert_has("h1", text: "Create New Organization")
      |> fill_in("Organization Name", with: "my big org")
      |> click_button("Create Organization")
      |> assert_path("/orgs/new")
      |> assert_has("p", text: "Oops, something went wrong! Please check the errors below.")
      |> assert_has(".help-block", text: "has invalid format")
    end

    test "creates a new org", %{conn: conn} do
      conn
      |> visit("/orgs/new")
      |> assert_has("h1", text: "Create New Organization")
      |> fill_in("Organization Name", with: "my-big-org")
      |> click_button("Create Organization")
      |> assert_path("/org/my-big-org")
      |> assert_has("h3", text: "my-big-org doesn’t have any products yet")
    end
  end
end
