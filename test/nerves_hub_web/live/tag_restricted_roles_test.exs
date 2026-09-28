defmodule NervesHubWeb.Live.TagRestrictedRolesTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
  alias NervesHub.CommandPalette
  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.Products

  setup %{org: org, product: product, firmware: firmware, user: user, device: hidden} do
    visible = Fixtures.device_fixture(org, product, firmware, %{tags: ["support"]})

    role =
      Fixtures.org_role_fixture(org, %{
        name: "Support",
        device_tags: ["support"],
        permissions: ["device:update", "device:reboot"]
      })

    {:ok, org_user} = Accounts.get_org_user(org, user)
    {:ok, _} = Accounts.change_org_user_role(org_user, role)

    %{visible: visible, hidden: hidden, role: role}
  end

  test "the device list shows only the devices the role's tags match", %{
    conn: conn,
    org: org,
    product: product,
    visible: visible,
    hidden: hidden
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/devices")
    |> assert_has("a", text: visible.identifier, timeout: 1_000)
    |> refute_has("a", text: hidden.identifier)
  end

  test "a device the role can't see isn't found", %{conn: conn, org: org, product: product, hidden: hidden} do
    assert_raise Ecto.NoResultsError, fn ->
      visit(conn, "/org/#{org.name}/#{product.name}/devices/#{hidden.identifier}")
    end
  end

  test "a device the role can see opens", %{conn: conn, org: org, product: product, visible: visible} do
    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{visible.identifier}")
    |> assert_has("h1", text: visible.identifier)
  end

  test "pages built from all of a product's devices are closed", %{conn: conn, org: org, product: product} do
    for page <-
          ~w(insights firmware archives deployment_groups deployment_groups/new notifications settings settings/health) do
      conn
      |> visit("/org/#{org.name}/#{product.name}/#{page}")
      |> assert_path("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("div", text: "Your role only gives you access to some of this organization's devices.")
    end
  end

  test "the sidebar leaves those pages out", %{conn: conn, org: org, product: product} do
    conn
    |> visit("/org/#{org.name}/#{product.name}/devices")
    |> assert_has("nav a", text: "Devices")
    |> refute_has("nav a", text: "Insights")
    |> refute_has("nav a", text: "Firmware")
    |> refute_has("nav a", text: "Deployment Groups")
  end

  test "device counts only include what the role can see", %{user: user, org: org, product: product} do
    scope = Scope.put_org(Scope.for_user(user), org)

    assert Products.get_product_counts(scope, product.id) == {0, 1}
    assert %{org: {0, 1}, products: products} = Accounts.get_org_device_counts(scope, org.id)
    assert products[product.id] == {0, 1}
  end

  test "the command palette offers only visible devices, and no deployment groups or firmware", %{
    user: user,
    org: org,
    visible: visible,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    scope = Scope.put_org(Scope.for_user(user), org)

    assert %{devices: [%{identifier: identifier}]} = CommandPalette.search(scope, "device-")
    assert identifier == visible.identifier

    assert %{deployment_groups: []} = CommandPalette.search(scope, deployment_group.name)
    assert %{firmware: []} = CommandPalette.search(scope, String.slice(firmware.uuid, 0, 8))
  end

  test "tag suggestions only come from visible devices", %{user: user, product: product} do
    assert Devices.distinct_tags_for_product(product, user) == ["support"]
  end

  describe "when access changes with the device page open" do
    test "the page is left once the device stops matching the role", %{
      conn: conn,
      org: org,
      product: product,
      visible: visible
    } do
      session = visit(conn, "/org/#{org.name}/#{product.name}/devices/#{visible.identifier}")

      {:ok, _} = Devices.update_device(visible, %{tags: ["production"]})

      {path, flash} = assert_redirect(session.view, 1_000)
      assert path == "/org/#{org.name}/#{product.name}/devices"
      assert flash["error"] == "You no longer have access to this device."
    end

    test "the page picks up a role edit without reloading", %{
      conn: conn,
      org: org,
      product: product,
      visible: visible,
      role: role
    } do
      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/devices/#{visible.identifier}")
        |> refute_has("button[aria-label='Add tag']")

      {:ok, _} = Accounts.OrgRoles.update_org_role(role, %{"permissions" => ["device:update", "device:tags"]})

      assert_has(session, "button[aria-label='Add tag']", timeout: 1_000)
    end
  end

  describe "changing tags" do
    test "needs its own permission", %{conn: conn, org: org, product: product, visible: visible, role: role} do
      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/devices/#{visible.identifier}")
        |> refute_has("button[aria-label='Add tag']")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(session.view, "remove-tag", %{"tag" => "support"}))

      {:ok, _} =
        Accounts.OrgRoles.update_org_role(role, %{"permissions" => ["device:update", "device:tags"]})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{visible.identifier}")
      |> assert_has("button[aria-label='Add tag']")
    end
  end
end
