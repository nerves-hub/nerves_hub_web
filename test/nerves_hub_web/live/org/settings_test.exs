defmodule NervesHubWeb.Live.Org.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Accounts

  test "updates org name", %{conn: conn, org: org} do
    conn
    |> visit("/org/#{org.name}/settings")
    |> assert_has("h1", text: "Organization Settings")
    |> fill_in("Organization Name", with: "MyAmazingOrganization", exact: false)
    |> click_button("Save Changes")
    |> assert_path("/org/MyAmazingOrganization/settings")
    |> assert_has("div", text: "Organization updated")
  end

  test "requires a name with no spaces", %{conn: conn, org: org} do
    conn
    |> visit("/org/#{org.name}/settings")
    |> assert_has("h1", text: "Organization Settings")
    |> fill_in("Organization Name", with: "My Amazing Organization", exact: false)
    |> click_button("Save Changes")
    |> assert_path("/org/#{org.name}/settings")
    |> assert_has(".help-block", text: "has invalid format")
  end

  describe "delete" do
    test "deletes the org", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/delete")
      |> assert_has("h3", text: "Are you absolutely sure?")
      |> fill_in("Please type #{org.name} to confirm.", with: org.name, exact: false)
      |> click_button("I understand the consequences, delete this organization")
      |> assert_path("/orgs")
      |> assert_has("div", text: "The Organization #{org.name} has successfully been deleted")

      org = NervesHub.Repo.reload(org)
      refute is_nil(org.deleted_at)
    end

    test "shows error when name does not match", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/delete")
      |> fill_in("Please type #{org.name} to confirm.", with: "wrong-name", exact: false)
      |> click_button("I understand the consequences, delete this organization")
      |> assert_path("/org/#{org.name}/settings/delete")
      |> assert_has("div", text: "Please type #{org.name} to confirm.")
    end

    test "shows error when soft_delete_org fails", %{conn: conn, org: org} do
      stub(Accounts, :soft_delete_org, fn _ ->
        {:error,
         %Ecto.Changeset{errors: [base: {"cannot delete", []}], data: %{}, changes: %{}, types: %{}, valid?: false}}
      end)

      conn
      |> visit("/org/#{org.name}/settings/delete")
      |> fill_in("Please type #{org.name} to confirm.", with: org.name, exact: false)
      |> click_button("I understand the consequences, delete this organization")
      |> assert_has("div",
        text: "There was an error deleting the Organization #{org.name}. Please contact support."
      )
    end
  end
end
