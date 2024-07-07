defmodule NervesHubWeb.Live.Org.SigningKeysTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  describe "list" do
    test "no signing keys", %{conn: conn, user: user} do
      org = Fixtures.org_fixture(user, %{name: "JoshCorp"})

      conn
      |> visit("/orgs/#{hashid(org)}/settings/keys")
      |> assert_has("h1", text: "Signing Keys")
      |> assert_has("a > span", text: "How to generate a signing key")
      |> refute_has("div .firmware-key")
    end

    test "1 signing key", %{conn: conn, org: org, org_key: org_key} do
      conn
      |> visit("/orgs/#{hashid(org)}/settings/keys")
      |> assert_has("h3", text: org_key.name)
      |> assert_has("h3", count: 1)
    end
  end

  describe "create signing key" do
    test "with valid data", %{conn: conn, org: org, user: user} do
      conn
      |> visit("/orgs/#{hashid(org)}/settings/keys/new")
      |> assert_has("h1", text: "New Signing Key")
      |> fill_in("Name", with: "my amazing key")
      |> fill_in("Key", with: "wouldn't you like to know!")
      |> click_button("Create Key")
      |> assert_path("/orgs/#{hashid(org)}/settings/keys")
      |> assert_has("div", text: "Signing Key created successfully.")
      |> assert_has("h3", text: "my amazing key")
      |> assert_has(".key-value", text: "wouldn't you like to know!")
      |> assert_has("div", text: "Created by: #{user.username}")
    end

    test "name is trimmed if there is extra space", %{conn: conn, org: org} do
      conn
      |> visit("/orgs/#{hashid(org)}/settings/keys/new")
      |> assert_has("h1", text: "New Signing Key")
      |> fill_in("Name", with: "    my    amazing     key    ")
      |> fill_in("Key", with: "wouldn't you like to know!")
      |> click_button("Create Key")
      |> assert_path("/orgs/#{hashid(org)}/settings/keys")
      |> assert_has("div", text: "Signing Key created successfully.")
      |> assert_has("h3", text: "my amazing key")
      |> assert_has(".key-value", text: "wouldn't you like to know!")
    end
  end

  describe "delete signing key" do
    test "removes the key", %{conn: conn, user: user} do
      org = Fixtures.org_fixture(user, %{name: "JoshCorp"})

      key = Fixtures.org_key_fixture(org, user)
      Fixtures.org_key_fixture(org, user)

      conn
      |> visit("/orgs/#{hashid(org)}/settings/keys")
      |> assert_has("h1", text: "Signing Keys")
      |> assert_has(".firmware-key div h3", count: 2)
      |> click_button("[phx-value-signing_key_id=\"#{key.id}\"]", "Delete")
      |> assert_has(".firmware-key div h3", count: 1)
      |> assert_has("div", text: "Signing Key deleted successfully.")
    end

    test "throws an error if the key is used by firmware", %{conn: conn, org: org, org_key: key} do
      conn
      |> visit("/orgs/#{hashid(org)}/settings/keys")
      |> assert_has("h1", text: "Signing Keys")
      |> assert_has(".firmware-key div h3", count: 1)
      |> click_button("[phx-value-signing_key_id=\"#{key.id}\"]", "Delete")
      |> assert_has("div",
        text: "Error deleting Signing Key : Firmware exists which uses the Signing Key"
      )
      |> assert_has(".firmware-key div h3", count: 1)
    end
  end
end
