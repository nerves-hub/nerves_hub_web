defmodule NervesHubWeb.Live.Org.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  test "updates org name", %{conn: conn, org: org} do
    conn
    |> visit("/orgs/#{org.name}/settings")
    |> assert_has("h1", text: "Organization Settings")
    |> fill_in("Organization Name", with: "MyAmazingOrganization")
    |> click_button("Save Changes")
    |> assert_path("/orgs/MyAmazingOrganization/settings")
    |> assert_has("div", text: "Organization updated")
  end

  test "requires a name with no spaces", %{conn: conn, org: org} do
    conn
    |> visit("/orgs/#{org.name}/settings")
    |> assert_has("h1", text: "Organization Settings")
    |> fill_in("Organization Name", with: "My Amazing Organization")
    |> click_button("Save Changes")
    |> assert_path("/orgs/#{org.name}/settings")
    |> assert_has(".help-block", text: "has invalid format")
  end
end
