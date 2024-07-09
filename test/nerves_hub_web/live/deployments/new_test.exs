defmodule NervesHubWeb.Live.Deployments.NewTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Fixtures

  describe "new deployment" do
    test "the happy path, with an audit log", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)

      firmware =
        Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, platform: "taramasalata"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/deployments/new")
      |> assert_has("h1", text: "Create Deployment")
      |> assert_has("option", text: "Choose a platform")
      |> select(firmware.platform, from: "Platform")
      |> fill_in("Deployment name", with: "Moussaka")
      |> fill_in("Tag(s) distributed to", with: "josh, lars")
      |> fill_in("Firmware version", with: firmware.id)
      |> click_button("Create Deployment")
      |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/deployments"))
      |> assert_has("h1", text: "Deployments")
      |> assert_has("div", text: "Deployment created")
      |> assert_has("a", text: "Moussaka")

      [%{resource_type: Deployment}] = AuditLogs.logs_by(user)
    end

    test "error message displayed if invalid firmware is selected", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)

      firmware =
        Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, platform: "taramasalata"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/deployments/new")
      |> select(firmware.platform, from: "Platform")
      |> unwrap(fn view ->
        view
        |> element("form")
        |> render_submit(%{deployment: %{"firmware_id" => -1}})
      end)
      |> assert_path("/org/#{org.name}/#{product.name}/deployments/new")
      |> assert_has("div", text: "Invalid firmware selected")
    end

    test "redirects to firmware upload firmware_id is passed and no firmwares are found" do
      user = Fixtures.user_fixture(%{email: "new@org.com"})
      org = Fixtures.org_fixture(user, %{name: "empty_org"})
      product = Fixtures.product_fixture(user, org)

      conn =
        build_conn()
        |> Map.put(:assigns, %{org: org})
        |> init_test_session(%{"auth_user_id" => user.id})

      conn
      |> visit("/org/#{org.name}/#{product.name}/deployments/new")
      |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/firmware/upload"))
      |> assert_has("h1", text: "Add Firmware")
      |> assert_has("div",
        text: "You must upload a firmware version before creating a deployment"
      )
    end
  end
end
