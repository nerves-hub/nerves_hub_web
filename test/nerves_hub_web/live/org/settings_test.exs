defmodule NervesHubWeb.Live.Org.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  test "updates org name", %{conn: conn, org: org} do
    conn
    |> visit("/orgs/#{hashid(org)}/settings")
    |> assert_has("h1", text: "Organization Settings")
    |> fill_in("Organization Name", with: "MyAmazingOrganization")
    |> click_button("Save Changes")
    |> assert_path("/orgs/#{hashid(org)}/settings")
    |> assert_has("div", text: "Organization updated")
  end

  test "requires a name with no spaces", %{conn: conn, org: org} do
    conn
    |> visit("/orgs/#{hashid(org)}/settings")
    |> assert_has("h1", text: "Organization Settings")
    |> fill_in("Organization Name", with: "My Amazing Organization")
    |> click_button("Save Changes")
    |> assert_path("/orgs/#{hashid(org)}/settings")
    |> assert_has(".help-block", text: "has invalid format")
  end

  describe "delete" do
    test "requires the user to confirm their username", %{conn: conn, org: org} do
      conn
      |> visit("/orgs/#{hashid(org)}/settings/delete")
      |> assert_has("h1", text: "Are you absolutely sure?")
      |> click_button("I understand the consequences, delete this organization")
      |> assert_path("/orgs/#{hashid(org)}/settings/delete")
      |> assert_has("div", text: "Please type #{org.name} to confirm.")

      org = NervesHub.Repo.reload(org)
      assert is_nil(org.deleted_at)
    end

    test "requires the user to confirm their username (it has to be correct)", %{
      conn: conn,
      org: org
    } do
      conn
      |> visit("/orgs/#{hashid(org)}/settings/delete")
      |> assert_has("h1", text: "Are you absolutely sure?")
      |> fill_in("Please type #{org.name} to confirm.", with: "#{org.name}-nah")
      |> click_button("I understand the consequences, delete this organization")
      |> assert_path("/orgs/#{hashid(org)}/settings/delete")
      |> assert_has("div", text: "Please type #{org.name} to confirm.")

      org = NervesHub.Repo.reload(org)
      assert is_nil(org.deleted_at)
    end

    test "deletes the org", %{conn: conn, org: org} do
      conn
      |> visit("/orgs/#{hashid(org)}/settings/delete")
      |> assert_has("h1", text: "Are you absolutely sure?")
      |> fill_in("Please type #{org.name} to confirm.", with: org.name)
      |> click_button("I understand the consequences, delete this organization")
      |> assert_path("/orgs")
      |> assert_has("div", text: "The Organization #{org.name} has successfully been deleted")

      org = NervesHub.Repo.reload(org)
      refute is_nil(org.deleted_at)
    end
  end
end
