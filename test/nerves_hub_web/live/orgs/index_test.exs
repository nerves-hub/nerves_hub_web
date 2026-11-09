defmodule NervesHubWeb.Live.Orgs.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.Pinning
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Workflows
  alias Phoenix.Socket.Broadcast

  test "user is redirected to login when trying to list their orgs, but the user isn't logged in" do
    build_conn()
    |> visit("/orgs")
    |> assert_path("/login")
    |> assert_has("div", text: "You must login to access this page.")
  end

  describe "onboarding" do
    setup do
      user = Fixtures.user_fixture(%{name: "Waffles Doe"})
      token = Accounts.create_user_session_token(user)

      %{conn: init_test_session(build_conn(), %{"user_token" => token}), user: user}
    end

    test "creates the first organization and product, then shows the product's devices", %{conn: conn} do
      conn
      |> visit(~p"/orgs")
      |> assert_has("h1", text: "Set up your first organization")
      |> assert_has("p", text: "Welcome, Waffles")
      |> fill_in("Organization name", with: "Doggos")
      |> fill_in("First product", with: "Ball")
      |> assert_has("#onboarding-url", text: "/org/Doggos/")
      |> assert_has("#onboarding-url", text: "Ball")
      |> click_button("Create organization and product")
      |> assert_path("/org/Doggos/Ball/devices")
    end

    test "suggests names from the user's name", %{conn: conn} do
      conn
      |> visit(~p"/orgs")
      |> assert_has("#onboarding-url", text: "/org/waffles-doe-team/")
      |> assert_has("#onboarding-url", text: "waffles-doeifier")
    end

    test "shows the error beside the field it belongs to", %{conn: conn} do
      conn
      |> visit(~p"/orgs")
      |> fill_in("Organization name", with: "")
      |> click_button("Create organization and product")
      |> assert_path("/orgs")
      |> assert_has("#onboarding-form .error-text", text: "can't be blank")
    end

    test "creates no organization when the product is refused", %{conn: conn} do
      conn
      |> visit(~p"/orgs")
      |> fill_in("Organization name", with: "Doggos")
      |> fill_in("First product", with: "")
      |> click_button("Create organization and product")
      |> assert_path("/orgs")
      |> assert_has("#onboarding-form .error-text", text: "can't be blank")

      assert {:error, :org_not_found} = Accounts.get_org_by_name("Doggos")
    end
  end

  describe "one organization" do
    test "is the page: its name, its counts and its products", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      Fixtures.device_fixture(org, product, firmware)
      connected = Fixtures.device_fixture(org, product, firmware)
      {:ok, connection} = Connections.device_connecting(connected.org_id, connected.product_id, connected.id)
      :ok = Connections.device_connected(connection.id)

      conn
      |> visit("/orgs")
      |> assert_has("h1", text: org.name)
      |> assert_has("header p", text: "1 product · 3 devices · 1 member")
      |> assert_has("header a", text: "Users")
      |> assert_has("header a", text: "Signing keys")
      |> assert_has("header a", text: "New organization")
      |> assert_has("#product-#{product.id}", text: product.name)
      |> assert_has("#product-#{product.id}", text: "1 deployment group", timeout: 2000)
      |> assert_has("#product-#{product.id} .online-count", text: "1", timeout: 2000)
      |> assert_has("#product-#{product.id}", text: "of 3")
    end

    test "says when nothing needs attention and nothing is pinned", %{conn: conn} do
      conn
      |> visit("/orgs")
      |> assert_has("#all-clear", text: "Nothing needs attention", timeout: 2000)
      |> assert_has("#pin-hint", text: "Pin a device from its page to keep it here")
    end

    test "offers New product only to someone who can create one", %{conn: conn, org: org} do
      viewer = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, viewer, %{role: :view})

      conn
      |> visit("/orgs")
      |> assert_has("a", text: "New product")

      build_conn()
      |> init_test_session(%{"user_token" => Accounts.create_user_session_token(viewer)})
      |> visit("/orgs")
      |> assert_has("h1", text: org.name)
      |> refute_has("a", text: "New product")
    end

    test "shows each product's health", %{conn: conn, org: org, product: product, firmware: firmware, fixture: fixture} do
      {:ok, _} = Health.save_device_health(%{device_id: fixture.device.id, status: :healthy})

      conn
      |> visit("/orgs")
      |> assert_has("#product-#{product.id}", text: "Healthy", timeout: 2000)

      warning = Fixtures.device_fixture(org, product, firmware)
      {:ok, _} = Health.save_device_health(%{device_id: warning.id, status: :warning})

      conn
      |> visit("/orgs")
      |> assert_has("#product-#{product.id}", text: "1 warning", timeout: 2000)
    end

    test "doesn't call a product healthy when none of its devices have reported", %{conn: conn, product: product} do
      conn
      |> visit("/orgs")
      |> assert_has("#product-#{product.id}", text: "Not reported", timeout: 2000)
    end
  end

  describe "needs attention" do
    test "lists unhealthy devices, linked to the product's filtered devices", %{
      conn: conn,
      org: org,
      product: product,
      fixture: fixture
    } do
      {:ok, _} = Health.save_device_health(%{device_id: fixture.device.id, status: :unhealthy})

      conn
      |> visit("/orgs")
      |> assert_has("#needs-attention .attention-item", text: "1 device is unhealthy", timeout: 2000)
      |> assert_has("#needs-attention a[href='/org/#{org.name}/#{product.name}/devices?health_status=unhealthy']")
      |> refute_has("#all-clear")
    end

    test "lists devices whose updates keep failing", %{conn: conn, org: org, product: product, fixture: fixture} do
      {:ok, _} =
        Devices.update_device(fixture.device, %{
          updates_blocked_until: DateTime.add(DateTime.utc_now(:second), 2, :hour),
          consecutive_failed_updates: 4
        })

      conn
      |> visit("/orgs")
      |> assert_has("#needs-attention .attention-item",
        text: "1 device stopped taking updates after repeated failures",
        timeout: 2000
      )
      |> assert_has("#needs-attention .attention-item", text: "updates resume in")
      |> assert_has("#needs-attention a[href='/org/#{org.name}/#{product.name}/devices?updates=failed-updates']")
    end

    test "lists a release waiting for approval, to review or to view", context do
      %{conn: conn, user: user, org: org, org_key: org_key, product: product, tmp_dir: tmp_dir} = context
      %{deployment_group: deployment_group} = context.fixture

      definition = %{"version" => 1, "steps" => [%{"name" => "Sign-off", "type" => "approval_required"}]}

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: definition}, user)

      next_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "2.4.1"})

      {:ok, {release, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{}, broadcast: false)

      [step | _] = Workflows.release_steps(release.id)
      {:ok, _} = Workflows.start_step(deployment_group, step)

      conn
      |> visit("/orgs")
      |> assert_has("#needs-attention .attention-item", text: "Release 2.4.1 is waiting for approval", timeout: 2000)
      |> assert_has("#needs-attention .attention-item", text: "#{deployment_group.name} · Sign-off")
      |> assert_has("#needs-attention a", text: "Review release")

      viewer = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, viewer, %{role: :view})

      build_conn()
      |> init_test_session(%{"user_token" => Accounts.create_user_session_token(viewer)})
      |> visit("/orgs")
      |> assert_has("#needs-attention a", text: "View release", timeout: 2000)
    end
  end

  describe "several organizations" do
    # The cached firmware file names its product "Hop", which is the product
    # it's uploaded to.
    defp another_org(user, name, device_count, context) do
      %{fw_path: fw_path, fwup_key_name: key_name, fwup_dir: fwup_dir} = context
      org = Fixtures.org_fixture(user, %{name: name})
      product = Fixtures.product_fixture(user, org, %{name: "Hop"})
      _org_key = Fixtures.org_key_fixture_from_existing(org, user, key_name, fwup_dir)
      firmware = Fixtures.firmware_fixture_from_file(org, fw_path)

      for _ <- 1..device_count//1, do: Fixtures.device_fixture(org, product, firmware)

      org
    end

    test "gives each its own section, largest first", %{conn: conn, user: user, org: org} = context do
      bigger = another_org(user, "Bigger", 3, context)

      conn
      |> visit("/orgs")
      |> assert_has("h1", text: "Organizations")
      |> assert_has("header p", text: "2 organizations · 2 products · 4 devices")
      |> assert_has("section#org-#{bigger.id} h2", text: "Bigger")
      |> assert_has("section#org-#{org.id} h2", text: org.name)
      |> refute_has("nav[aria-label='Organizations']")

      {:ok, _view, html} = live(conn, "/orgs")
      {bigger_at, _} = :binary.match(html, "org-title-#{bigger.id}")
      {smaller_at, _} = :binary.match(html, "org-title-#{org.id}")
      assert bigger_at < smaller_at
    end

    test "sums them up from three", %{conn: conn, user: user} = context do
      another_org(user, "Second", 2, context)
      another_org(user, "Third", 1, context)

      conn
      |> visit("/orgs")
      |> assert_has("nav[aria-label='Organizations'] a", count: 3)
    end

    test "lists the rest in a table past four", %{conn: conn, user: user} = context do
      for {name, count} <- [{"A", 5}, {"B", 4}, {"C", 3}, {"D", 2}], do: another_org(user, name, count, context)
      smallest = another_org(user, "Empty", 0, context)

      conn
      |> visit("/orgs")
      |> assert_has("section[id^='org-']", count: 4)
      |> assert_has("#other-orgs", text: "Other organizations")
      |> assert_has("#other-org-#{smallest.id}", text: "Empty")
      |> assert_has("#other-org-#{smallest.id}", text: "No devices yet")
    end
  end

  describe "pinned devices" do
    test "lists them with their product, firmware and state", %{conn: conn, user: user, fixture: fixture} do
      {:ok, _} = Pinning.pin_device(user.id, fixture.device.id)

      conn
      |> visit("/orgs")
      |> assert_has("#pinned-#{fixture.device.id}", text: fixture.device.identifier)
      |> assert_has("#pinned-#{fixture.device.id}", text: fixture.product.name)
      |> assert_has("#pinned-#{fixture.device.id}", text: "Offline")
      |> refute_has("#pin-hint")
    end

    test "toggle-expand-devices shows all pinned devices when more than limit", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      firmware: firmware
    } do
      for _ <- 1..6 do
        device = Fixtures.device_fixture(org, product, firmware)
        {:ok, _} = Pinning.pin_device(user.id, device.id)
      end

      conn
      |> visit("/orgs")
      |> assert_has("button", text: "Show all 6 devices")
      |> click_button("Show all 6 devices")
      |> assert_has("button", text: "Show less")
    end

    test "connection:change broadcast updates device status", %{conn: conn, user: user, fixture: fixture} do
      device = fixture.device
      {:ok, _} = Pinning.pin_device(user.id, device.id)

      conn
      |> visit("/orgs")
      |> assert_has("#pinned-#{device.id}", text: "Offline")
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{
          topic: "internal:device:#{device.id}",
          event: "connection:change",
          payload: %{device_id: device.identifier, status: "online"}
        })

        render(view)
      end)
      |> assert_has("#pinned-#{device.id}", text: "No health reported")
    end
  end
end
