defmodule NervesHubWeb.ProductSidebarTest do
  # Each test visits the notifications page: it renders the same sidebar as
  # every other product page, without the devices index's async queries, which
  # outlive the test process.
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts
  alias NervesHub.Devices.Health
  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.ProductNotifications
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  defp visit_product(conn, org, product), do: visit(conn, "/org/#{org.name}/#{product.name}/notifications")

  describe "the product header" do
    test "names the organization and the product, and counts the devices online", %{
      conn: conn,
      org: org,
      product: product
    } do
      conn
      |> visit_product(org, product)
      |> assert_has("#product-sidebar a[href='/org/#{org.name}']", text: org.name)
      |> assert_has("#product-switcher-toggle", text: product.name)
      |> assert_has("#product-online", text: "0 / 1")
    end

    test "counts connected devices online, and every other device that isn't deleted as offline", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      # The setup's device has never connected, so it has no connection row.
      online = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_connection_fixture(online, %{status: :connected})
      offline = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_connection_fixture(offline, %{status: :disconnected})
      deleted = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_connection_fixture(deleted, %{status: :connected})
      {:ok, _} = NervesHub.Devices.delete_device(deleted)

      conn
      |> visit_product(org, product)
      |> assert_has("#product-online", text: "1 / 3")
    end

    test "a phone's top bar names the product and the page, and offers the user menu", %{
      conn: conn,
      org: org,
      product: product
    } do
      # The notifications page has its own top bar, which takes the phone
      # title, so this checks another product page.
      conn
      |> visit("/org/#{org.name}/#{product.name}/scripts")
      |> assert_has("#phone-title", text: "#{product.name} / Support scripts")
      |> assert_has("#phone-user-menu a", text: "Log out")
    end

    test "a page with its own breadcrumb leaves the phone title out", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: firmware.version)
      |> refute_has("#phone-title")
    end
  end

  describe "the user menu" do
    test "links to the account, its access tokens, the organizations and logging out", %{
      conn: conn,
      user: user,
      org: org,
      product: product
    } do
      conn
      |> visit_product(org, product)
      |> assert_has("#user-menu-toggle", text: user.name)
      |> assert_has("#user-menu a[href='/account']", text: "Account")
      |> assert_has("#user-menu a[href='/account/tokens']", text: "Access tokens")
      |> assert_has("#user-menu a[href='/orgs']", text: "Organizations")
      |> assert_has("#user-menu a[href='/logout']", text: "Log out")
      |> assert_has("#user-menu button[data-theme-option='system']")
    end
  end

  describe "the links' statuses" do
    test "say nothing when there's nothing to look at", %{conn: conn, org: org, product: product} do
      conn
      |> visit_product(org, product)
      |> refute_has("#nav-devices", text: "unhealthy")
      |> refute_has("#nav-deployment-groups", text: "awaiting approval")
      |> refute_has("#product-sidebar[data-attention]")
    end

    test "count unhealthy devices under Devices", %{conn: conn, org: org, product: product, device: device} do
      {:ok, _} = Health.save_device_health(%{device_id: device.id, status: :unhealthy})

      conn
      |> visit_product(org, product)
      |> assert_has("#nav-devices", text: "1 unhealthy")
      |> assert_has("#product-sidebar[data-attention='alert']")
    end

    test "count warnings when no device is unhealthy", %{conn: conn, org: org, product: product, device: device} do
      {:ok, _} = Health.save_device_health(%{device_id: device.id, status: :warning})

      conn
      |> visit_product(org, product)
      |> assert_has("#nav-devices", text: "1 warning")
      |> assert_has("#product-sidebar[data-attention='warning']")
    end

    test "count the deployment groups, and name a release awaiting approval", context do
      %{conn: conn, user: user, org: org, org_key: org_key, product: product, tmp_dir: tmp_dir} = context

      conn
      |> visit_product(org, product)
      |> assert_has("#nav-deployment-groups [data-count]", text: "1", exact: true)

      definition = %{"version" => 1, "steps" => [%{"name" => "Sign-off", "type" => "approval_required"}]}

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(context.deployment_group, %{workflow_definition: definition}, user)

      next_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "2.4.1"})

      {:ok, {release, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{}, broadcast: false)

      [step | _] = Workflows.release_steps(release.id)
      {:ok, _} = Workflows.start_step(deployment_group, step)

      conn
      |> visit_product(org, product)
      |> assert_has("#nav-deployment-groups", text: "2.4.1 awaiting approval")
      |> assert_has("#product-sidebar[data-attention='waiting']")
    end

    test "count notifications", %{conn: conn, org: org, product: product} do
      _ = ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)

      conn
      |> visit_product(org, product)
      |> assert_has("#nav-notifications [data-count]", text: "1", exact: true)
      # News, not a problem: it doesn't put a dot on the menu button.
      |> refute_has("#product-sidebar[data-attention]")
    end
  end

  describe "the product switcher" do
    test "lists the organization's products with their health, and the other organizations", context do
      %{conn: conn, user: user, org: org, product: product, device: device} = context
      {:ok, _} = Health.save_device_health(%{device_id: device.id, status: :unhealthy})
      Fixtures.product_fixture(user, org, %{name: "Valve"})
      Fixtures.org_fixture(user, %{name: "Elsewhere"})

      conn
      |> visit_product(org, product)
      |> refute_has("#product-switcher")
      |> click_button("#product-switcher-toggle", product.name)
      |> within("#product-switcher", fn session ->
        session
        |> assert_has("a[aria-current='page']", text: "#{product.name} 1 unhealthy")
        |> assert_has("a", text: "Valve No devices yet")
        |> assert_has("a[href='/org/Elsewhere']", text: "Elsewhere")
        |> assert_has("a[href='/org/#{org.name}/new']", text: "New product")
      end)
    end

    test "colours a product's line as an alert when it has open errors, even if its devices only warn", context do
      %{conn: conn, org: org, product: product, device: device} = context
      {:ok, _} = Health.save_device_health(%{device_id: device.id, status: :warning})
      product = product |> Product.changeset(%{"extensions" => %{"error_reports" => true}}) |> Repo.update!()
      now = DateTime.utc_now()

      %{product_id: product.id, fingerprint: "f1", fingerprint_version: 1, kind: "error", reason: "boom"}
      |> Map.merge(%{first_seen_at: now, last_seen_at: now})
      |> ErrorGroup.create_changeset()
      |> Repo.insert!()

      conn
      |> visit_product(org, product)
      |> click_button("#product-switcher-toggle", product.name)
      |> assert_has("#product-switcher a[aria-current='page'] .text-alert-content", text: "1 warning · 1 open error")
    end

    test "finds a product by name", %{conn: conn, user: user, org: org, product: product} do
      Fixtures.product_fixture(user, org, %{name: "Valve"})

      conn
      |> visit_product(org, product)
      |> click_button("#product-switcher-toggle", product.name)
      |> fill_in("Find a product", with: "val")
      |> assert_has("#product-switcher a", text: "Valve")
      |> refute_has("#product-switcher a", text: product.name)
    end

    test "leaves out New product for a role that can't make one", %{conn: conn, user: user, org: org, product: product} do
      {:ok, org_user} = Accounts.get_org_user(org, user)
      {:ok, _} = Accounts.change_org_user_role(org_user, :view)

      conn
      |> visit_product(org, product)
      |> click_button("#product-switcher-toggle", product.name)
      |> refute_has("#product-switcher a", text: "New product")
    end
  end
end
