defmodule NervesHubWeb.Live.Org.SigningKeysTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Support.EspIdf

  describe "list" do
    test "no signing keys", %{conn: conn, user: user} do
      org = Fixtures.org_fixture(user, %{name: "JoshCorp"})

      conn
      |> visit("/org/#{org.name}/settings/keys")
      |> assert_has("h1", text: "Signing Keys")
      |> assert_has("a > span", text: "How to generate a signing key")
      |> refute_has("div .firmware-key")
    end

    test "available signing keys are listed", %{conn: conn, org: org, org_key: org_key} do
      conn
      |> visit("/org/#{org.name}/settings/keys")
      |> assert_has("h3", text: org_key.name)
    end
  end

  describe "create signing key" do
    test "with valid data", %{conn: conn, org: org, user: user} do
      conn
      |> visit("/org/#{org.name}/settings/keys/new")
      |> assert_has("h1", text: "New Signing Key")
      |> fill_in("Name", with: "my amazing key")
      |> fill_in("Key", with: "FMBdNKrU3qlyErQtpqxsq50nGAXz03DCeEXPt2iKBe0=")
      |> click_button("Create Key")
      |> assert_path("/org/#{org.name}/settings/keys")
      |> assert_has("div", text: "Signing Key created successfully.")
      |> assert_has("h3", text: "my amazing key")
      |> assert_has("div", text: "FMBdNKrU3qlyErQtpqxsq50nGAXz03DCeEXPt2iKBe0=")
      |> assert_has("div", text: "Created by: #{user.name} (#{user.email})")
    end

    test "name is trimmed if there is extra space", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/keys/new")
      |> assert_has("h1", text: "New Signing Key")
      |> fill_in("Name", with: "    my    amazing     key    ")
      |> fill_in("Key", with: "FMBdNKrU3qlyErQtpqxsq50nGAXz03DCeEXPt2iKBe0=")
      |> click_button("Create Key")
      |> assert_path("/org/#{org.name}/settings/keys")
      |> assert_has("div", text: "Signing Key created successfully.")
      |> assert_has("h3", text: "my amazing key")
      |> assert_has("div", text: "FMBdNKrU3qlyErQtpqxsq50nGAXz03DCeEXPt2iKBe0=")
    end
  end

  describe "create an ESP-IDF signing key" do
    test "accepts a PEM RSA-3072 public key", %{conn: conn, org: org} do
      pem = EspIdf.signing_public_key()

      conn
      |> visit("/org/#{org.name}/settings/keys/new")
      |> select("Scheme", option: "ESP-IDF Secure Boot v2 (RSA-3072)")
      |> fill_in("Name", with: "esp release key")
      |> fill_in("Key", with: pem)
      |> click_button("Create Key")
      |> assert_path("/org/#{org.name}/settings/keys")
      |> assert_has("div", text: "Signing Key created successfully.")
      |> assert_has("h3", text: "esp release key")
      |> assert_has("code", text: "secure-boot-v2-rsa")
    end

    # The Ed25519 check would reject a PEM and vice versa, so the scheme has to
    # reach the changeset — not just be stored after validation.
    test "rejects an Ed25519 key submitted as RSA", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/keys/new")
      |> select("Scheme", option: "ESP-IDF Secure Boot v2 (RSA-3072)")
      |> fill_in("Name", with: "wrong scheme")
      |> fill_in("Key", with: "FMBdNKrU3qlyErQtpqxsq50nGAXz03DCeEXPt2iKBe0=")
      |> click_button("Create Key")
      |> assert_has("div", text: "expected a PEM-encoded RSA public key")
    end

    test "rejects a PEM submitted as Ed25519", %{conn: conn, org: org} do
      pem = EspIdf.signing_public_key()

      conn
      |> visit("/org/#{org.name}/settings/keys/new")
      |> fill_in("Name", with: "wrong scheme")
      |> fill_in("Key", with: pem)
      |> click_button("Create Key")
      |> assert_has("div", text: "valid Ed25519 public key")
    end

    # A PEM is 600+ bytes of base64; dumping it into the list tells nobody
    # anything and pushes everything else off the row.
    test "shows only the boundary lines of a PEM in the list", %{conn: conn, org: org, user: user} do
      key = Fixtures.esp_idf_key_fixture(org, user)

      conn
      |> visit("/org/#{org.name}/settings/keys")
      |> assert_has("h3", text: key.name)
      |> assert_has("div", text: "BEGIN PUBLIC KEY")
      |> assert_has("div", text: "END PUBLIC KEY")
    end
  end

  describe "delete signing key" do
    test "removes the key", %{conn: conn, user: user} do
      org = Fixtures.org_fixture(user, %{name: "JoshCorp"})

      key1 = Fixtures.org_key_fixture(org, user)
      key2 = Fixtures.org_key_fixture(org, user)

      conn
      |> visit("/org/#{org.name}/settings/keys")
      |> assert_has("h1", text: "Signing Keys")
      |> assert_has("h3", text: key1.name)
      |> assert_has("h3", text: key2.name)
      |> click_button("[phx-value-signing_key_id=\"#{key1.id}\"]", "Delete")
      |> assert_has("h3", text: key2.name)
      |> refute_has("h3", text: key1.name)
      |> assert_has("div", text: "Signing Key deleted successfully.")
    end

    test "throws an error if the key is used by firmware", %{conn: conn, org: org, org_key: key} do
      conn
      |> visit("/org/#{org.name}/settings/keys")
      |> assert_has("h1", text: "Signing Keys")
      |> assert_has("h3", text: key.name)
      |> click_button("[phx-value-signing_key_id=\"#{key.id}\"]", "Delete")
      |> assert_has("div",
        text: "Error deleting Signing Key : Firmware exists which uses the Signing Key"
      )
      |> assert_has("h3", text: key.name)
    end
  end
end
