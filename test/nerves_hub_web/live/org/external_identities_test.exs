defmodule NervesHubWeb.Live.Org.ExternalIdentitiesTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Devices.ExternalIdentities
  alias NervesHub.Fixtures

  @endpoint_id "c8924b6c9b7a8528b1365ebec4b2e43b6edebef684f8521f12b8caaf6e1b2302"

  setup do
    previous = Application.get_env(:nerves_hub, :external_identities_enabled, false)
    Application.put_env(:nerves_hub, :external_identities_enabled, true)
    on_exit(fn -> Application.put_env(:nerves_hub, :external_identities_enabled, previous) end)
  end

  defp path(org), do: "/org/#{org.name}/settings/iroh-endpoints"

  describe "the feature flag" do
    test "hides the page entirely when off", %{conn: conn, org: org} do
      Application.put_env(:nerves_hub, :external_identities_enabled, false)

      # Not merely hidden from the sidebar: typing the URL has to fail too, or
      # the flag is decoration.
      assert_raise NervesHubWeb.NotFoundError, fn ->
        conn |> visit(path(org))
      end
    end

    test "keeps the link out of the sidebar when off", %{conn: conn, org: org} do
      Application.put_env(:nerves_hub, :external_identities_enabled, false)

      conn
      |> visit("/org/#{org.name}/settings/keys")
      |> refute_has("a", text: "Iroh Endpoints")
    end

    test "shows the link when on", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/keys")
      |> assert_has("a", text: "Iroh Endpoints")
    end
  end

  describe "listing" do
    test "says so when there is nothing yet", %{conn: conn, org: org} do
      conn
      |> visit(path(org))
      |> assert_has("h1", text: "Iroh Endpoints")
      |> assert_has("p", text: "No endpoints yet")
    end

    test "shows a device's endpoint and which device it is", %{conn: conn, org: org, device: device} do
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: @endpoint_id})

      conn
      |> visit(path(org))
      |> assert_has("div", text: String.slice(@endpoint_id, 0, 16))
      |> assert_has("span", text: device.identifier)
      |> assert_has("span", text: "reported by device")
    end

    test "shows an endpoint registered by hand as unassigned", %{conn: conn, org: org} do
      {:ok, _} = ExternalIdentities.register(org.id, :iroh, %{identifier: @endpoint_id})

      conn
      |> visit(path(org))
      |> assert_has("span", text: "Unassigned")
      |> assert_has("span", text: "registered")
    end

    test "does not show another organisation's endpoints", %{conn: conn, org: org, user: user} do
      other_org = Fixtures.org_fixture(user, %{name: "SomeoneElse"})
      {:ok, _} = ExternalIdentities.register(other_org.id, :iroh, %{identifier: @endpoint_id})

      conn
      |> visit(path(org))
      |> assert_has("p", text: "No endpoints yet")
    end
  end

  describe "search and filter" do
    setup %{org: org, device: device} do
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: @endpoint_id})
      {:ok, _} = ExternalIdentities.register(org.id, :iroh, %{identifier: String.duplicate("ab", 32)})
      :ok
    end

    test "matches the start of an endpoint id", %{conn: conn, org: org} do
      # The front is the half an operator has, since that is what a log line
      # shows them.
      conn
      |> visit(path(org))
      |> fill_in("Search endpoints", with: String.slice(@endpoint_id, 0, 8))
      |> assert_has("div", text: String.slice(@endpoint_id, 0, 16))
      |> refute_has("div", text: "abababababababab")
    end

    test "matches a device identifier", %{conn: conn, org: org, device: device} do
      conn
      |> visit(path(org))
      |> fill_in("Search endpoints", with: device.identifier)
      |> assert_has("span", text: device.identifier)
      |> refute_has("div", text: "abababababababab")
    end

    test "filters to endpoints with no owner", %{conn: conn, org: org} do
      conn
      |> visit(path(org))
      |> select("Unassigned", from: "Owner")
      |> assert_has("div", text: "abababababababab")
      |> refute_has("div", text: String.slice(@endpoint_id, 0, 16))
    end
  end

  describe "registering" do
    test "records an endpoint against the organisation", %{conn: conn, org: org} do
      conn
      |> visit(path(org))
      |> click_button("Register Endpoint")
      |> fill_in("Endpoint id", with: @endpoint_id)
      |> submit()
      |> assert_has("div", text: "Endpoint registered")

      assert {:ok, %{org_id: org_id, owner: "org"}} =
               ExternalIdentities.get_owner_by_identifier(:iroh, @endpoint_id)

      assert org_id == org.id
    end

    test "refuses one already registered, without saying where", %{conn: conn, org: org, user: user} do
      other_org = Fixtures.org_fixture(user, %{name: "AlreadyHasIt"})
      {:ok, _} = ExternalIdentities.register(other_org.id, :iroh, %{identifier: @endpoint_id})

      # Whether another organisation holds a key is that organisation's
      # business, so the message says it is taken and nothing more.
      conn
      |> visit(path(org))
      |> click_button("Register Endpoint")
      |> fill_in("Endpoint id", with: @endpoint_id)
      |> submit()
      # Says it is taken and nothing more. Whether another organisation holds a
      # key is that organisation's business, so the message names no one — the
      # page cannot assert that on its own, since the org switcher lists every
      # organisation this user belongs to.
      |> assert_has("div", text: "already registered")
      |> assert_has("div", text: "it will be claimed the next time that device connects")
    end

    test "attaches the endpoint to a person when one is chosen", %{conn: conn, org: org, user: user} do
      conn
      |> visit(path(org))
      |> click_button("Register Endpoint")
      |> fill_in("Endpoint id", with: @endpoint_id)
      |> select(user.name, from: "Belongs to")
      |> submit()
      |> assert_has("div", text: "Endpoint registered")
      |> assert_has("span", text: user.name)

      assert {:ok, %{owner: "org_user", user_id: user_id}} =
               ExternalIdentities.get_owner_by_identifier(:iroh, @endpoint_id)

      assert user_id == user.id
    end

    test "refuses a membership from another organisation", %{org: org, user: user} do
      # Only reachable by a crafted request — the select never offers it — but
      # the id arrives from a form, so it is a request rather than a fact.
      other_org = Fixtures.org_fixture(user, %{name: "Elsewhere"})

      other_member =
        NervesHub.Repo.get_by!(OrgUser, org_id: other_org.id, user_id: user.id)

      assert {:error, :invalid_member} =
               ExternalIdentities.register(org.id, :iroh, %{
                 identifier: @endpoint_id,
                 org_user_id: other_member.id
               })
    end

    test "a view-only member cannot register", %{conn: conn, org: org, user: user} do
      # Registering decides which organisation a key answers for, so it takes
      # the manage role.
      org_user = NervesHub.Repo.get_by!(OrgUser, org_id: org.id, user_id: user.id)
      {:ok, _} = NervesHub.Accounts.change_org_user_role(org_user, :view)

      conn
      |> visit(path(org))
      |> refute_has("button", text: "Register Endpoint")
    end
  end

  describe "removing" do
    test "removes an endpoint", %{conn: conn, org: org} do
      {:ok, _} = ExternalIdentities.register(org.id, :iroh, %{identifier: @endpoint_id})

      conn
      |> visit(path(org))
      |> click_button("Remove")
      |> assert_has("div", text: "Endpoint removed")

      assert {:error, :not_found} =
               ExternalIdentities.get_owner_by_identifier(:iroh, @endpoint_id)
    end
  end
end
