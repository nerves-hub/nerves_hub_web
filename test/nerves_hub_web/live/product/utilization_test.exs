defmodule NervesHubWeb.Live.Product.UtilizationTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Products.Utilization

  @moduletag :tmp_dir

  defp utilization_path(org, product), do: "/org/#{org.name}/#{product.name}/settings/utilization"

  describe "the tab" do
    # The fixtures give the product firmware and a device with a certificate.
    # Its deployment group is off, and logging is on with nothing logged.
    test "shows the score on every settings page", %{conn: conn, org: org, product: product} do
      assert Utilization.score(product) == %{done: 2, total: 13}

      for page <- ["", "/health", "/api_keys", "/utilization"] do
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings#{page}")
        |> assert_has("#utilization-tab-score", text: "(2/13)")
        |> assert_has("nav a", text: "Utilization")
      end
    end

    test "is reached from the product's settings", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> click_link("Utilization")
      |> assert_path(utilization_path(org, product))
      |> assert_has("nav a[aria-current='page']", text: "Utilization")
    end

    test "counts a key created on the API keys page", %{conn: conn, org: org, product: product, user: user} do
      Fixtures.api_key_fixture(product, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings/api_keys")
      |> assert_has("#utilization-tab-score", text: "(3/13)")
    end

    test "follows an extension turned on in General", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("#utilization-tab-score", text: "(2/13)")
      |> unwrap(fn view ->
        render_click(view, "update-extension", %{"extension" => "error_reports", "value" => "on"})
      end)
      |> assert_has("#utilization-tab-score", text: "(3/13)")
    end
  end

  describe "the report" do
    test "shows the score and each group", %{conn: conn, org: org, product: product} do
      conn
      |> visit(utilization_path(org, product))
      |> assert_has("#utilization-score", text: "2")
      |> assert_has("#utilization-score", text: "of 13")
      |> assert_has("#utilization-score h2", text: "11 recommended features are still to turn on.")
      |> assert_has("#utilization-score", text: "nh checklist #{product.name}")
      |> assert_has("#utilization-authentication #utilization-device_auth[data-status='done']")
      |> assert_has(
        "#utilization-recommended #utilization-signed_firmware[data-status='done'] [role='img'][aria-label='In use']"
      )
      |> assert_has(
        "#utilization-recommended #utilization-logging[data-status='attention'] [role='img'][aria-label='Warning']"
      )
      |> assert_has(
        "#utilization-recommended #utilization-deployments[data-status='todo'] [role='img'][aria-label='Not in use']"
      )
      |> assert_has(
        "#utilization-recommended #utilization-ci_api_key[data-status='todo'] [role='img'][aria-label='Not in use']"
      )
      |> assert_has("#utilization-optional h2", text: "Optional bonuses")
      |> assert_has(
        "#utilization-optional #utilization-archives[data-status='todo'] [role='img'][aria-label='Not in use']"
      )
      |> refute_has("#utilization-recommended #utilization-archives")
    end

    test "says how devices authenticate, shared secrets as a warning", context do
      %{conn: conn, org: org, product: product, user: user, tmp_dir: dir} = context

      org_key = Fixtures.org_key_fixture(org, user, dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: dir})

      Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})
      with_certificate = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})
      Fixtures.device_certificate_fixture(with_certificate, X509.PrivateKey.new_ec(:secp256r1))

      conn
      |> visit(utilization_path(org, product))
      |> assert_has("#auth-method-shared_secret[data-level='warning']", text: "Shared Secret")
      |> assert_has("#auth-method-shared_secret .text-warning-content", text: "1")
      |> assert_has("#auth-method-local_cert[data-level='good']", text: "LocalCert")
      |> assert_has("#auth-method-local_cert .text-success-content", text: "2")
      |> assert_has("#auth-method-nerves_key[data-level='good']", text: "NervesKey")
      |> assert_has("#utilization-device_auth[data-status='attention'] [role='img'][aria-label='Warning']")
      |> assert_has("#utilization-device_auth",
        text: "1 of 3 devices connects with a secret shared by the whole product."
      )
    end

    test "links each item to its documentation, and to where it is turned on", %{conn: conn, org: org, product: product} do
      conn
      |> visit(utilization_path(org, product))
      |> assert_has("#utilization-delta_updates a[href='https://docs.nerves-hub.org/management/delta-updates']",
        text: "Documentation"
      )
      |> assert_has("#utilization-delta_updates a[href='/org/#{org.name}/#{product.name}/deployment_groups']",
        text: "Deployment groups"
      )
      |> assert_has("#utilization-two_factor a[href='/org/#{org.name}/settings']", text: "Organization settings")
    end

    test "the headline counts what is left", %{conn: conn, org: org, product: product} do
      {:ok, _} = Products.enable_extension_setting(product, "error_reports")

      conn
      |> visit(utilization_path(org, product))
      |> assert_has("#utilization-score h2", text: "10 recommended features are still to turn on.")
    end
  end

  describe "access" do
    test "a member limited to some devices can't open it", %{conn: conn, org: org, product: product, user: user} do
      role = Fixtures.org_role_fixture(org, %{name: "Lab", permissions: ["device:update"], device_tags: ["lab"]})
      {:ok, org_user} = NervesHub.Accounts.get_org_user(org, user)
      {:ok, _} = NervesHub.Accounts.change_org_user_role(org_user, role)

      conn
      |> visit(utilization_path(org, product))
      |> assert_path("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("div", text: "Your role only gives you access to some of this organization's devices.")
    end
  end
end
