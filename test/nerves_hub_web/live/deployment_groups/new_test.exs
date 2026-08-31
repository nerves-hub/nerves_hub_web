defmodule NervesHubWeb.Live.DelploymentGroups.NewTest do
  use NervesHubWeb.ConnCase.Browser, async: true
  use Mimic

  import Ecto.Query, only: [from: 2]

  alias NervesHub.AuditLogs
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentGroup.Conditions
  alias NervesHub.Repo

  setup context do
    conn =
      context.conn
      |> visit("/org/#{context.org.name}/#{context.product.name}/deployment_groups/new")

    %{context | conn: conn}
  end

  describe "previous test suite" do
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
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/new")
      |> assert_has("h1", text: "Add Deployment Group")
      |> assert_has("option", text: "Choose a platform")
      |> select("Platform", option: firmware.platform)
      |> select("Architecture", option: firmware.architecture)
      |> fill_in("Name", with: "Moussaka")
      |> fill_in("Tag(s) distributed to", with: "josh, lars")
      |> select("Firmware", option: firmware.uuid, exact_option: false)
      |> click_button("Save changes")
      |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/deployment_groups/Moussaka"))
      |> assert_has("div", text: "Deployment Group created")
      |> assert_has("h1", text: "Moussaka")

      [%{resource_type: DeploymentGroup}, %{resource_type: DeploymentGroup}] = AuditLogs.logs_by(user)
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
        Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, platform: "snoot", architecture: "boop"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/new")
      |> select("Platform", option: firmware.platform)
      |> select("Architecture", option: firmware.architecture)
      |> unwrap(fn view ->
        view
        |> element("#new-deployment")
        |> render_submit(%{deployment_group: %{"firmware_id" => -1}})
      end)
      |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/new")
      |> assert_has("span", text: "can't be blank")
    end

    test "redirects to firmware upload firmware_id is passed and no firmwares are found" do
      user = Fixtures.user_fixture(%{email: "new@org.com"})
      org = Fixtures.org_fixture(user, %{name: "empty_org"})
      product = Fixtures.product_fixture(user, org)

      token = NervesHub.Accounts.create_user_session_token(user)

      conn =
        build_conn()
        |> Map.put(:assigns, %{org: org})
        |> init_test_session(%{"user_token" => token})

      conn
      |> visit(~p"/org/#{org}/#{product}/deployment_groups/new")
      |> assert_has("span", text: "Please upload your first firmware before creating a deployment group.")
    end
  end

  test "delta updates are enabled by default", %{conn: conn, org: org, product: product} do
    conn
    |> assert_has("input[name='deployment_group[delta_updatable]']", value: "true")
    |> fill_in("Name", with: "Canaries")
    |> select("Platform", option: "platform")
    |> select("Architecture", option: "x86_64")
    |> select("Firmware", option: "1.0.0", exact_option: false)
    |> submit()
    |> assert_path(~p"/org/#{org}/#{product}/deployment_groups/Canaries")

    deployment_group = Repo.one!(from(d in DeploymentGroup, where: d.name == "Canaries"))
    assert deployment_group.delta_updatable
  end

  test "disable delta updates when creating a deployment group", %{conn: conn, org: org, product: product} do
    conn
    |> assert_has("input[name='deployment_group[delta_updatable]']", checked: true)
    |> fill_in("Name", with: "Canaries")
    |> uncheck("Delta updates")
    |> select("Platform", option: "platform")
    |> select("Architecture", option: "x86_64")
    |> select("Firmware", option: "1.0.0", exact_option: false)
    |> submit()
    |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/Canaries")

    deployment_group = Repo.one!(from(d in DeploymentGroup, where: d.name == "Canaries"))
    refute deployment_group.delta_updatable
  end

  test "can update only version", %{conn: conn, org: org, product: product, fixture: fixture} do
    conn
    |> fill_in("Name", with: "Canaries")
    |> select("Platform", option: "platform")
    |> select("Architecture", option: "x86_64")
    |> select("Firmware", option: "1.0.0", exact_option: false)
    |> fill_in("Tag(s) distributed to", with: "a, b")
    |> fill_in("Version requirement", with: "1.2.3")
    |> submit()
    |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/Canaries")

    deployment_group = ManagedDeployments.get_by_product_and_name!(product, "Canaries")

    assert deployment_group.current_release.firmware_id == fixture.firmware.id
    assert deployment_group.conditions == %Conditions{version: "1.2.3", tags: ["a", "b"]}
  end

  test "errors display for invalid version", %{conn: conn, org: org, product: product} do
    conn
    |> fill_in("Name", with: "Canaries")
    |> select("Platform", option: "platform")
    |> select("Architecture", option: "x86_64")
    |> select("Firmware", option: "1.0.0", exact_option: false)
    |> fill_in("Tag(s) distributed to", with: "a, b")
    |> fill_in("Version requirement", with: "1.0")
    |> submit()
    |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/new")
    |> assert_has("p", text: "must be valid Elixir version requirement string")
  end

  test "can set notes when creating a deployment group", %{conn: conn, org: org, product: product} do
    conn
    |> fill_in("Name", with: "Canaries")
    |> fill_in("Notes", with: "Created for the summer campaign hardware batch")
    |> select("Platform", option: "platform")
    |> select("Architecture", option: "x86_64")
    |> select("Firmware", option: "1.0.0", exact_option: false)
    |> submit()
    |> assert_path(~p"/org/#{org}/#{product}/deployment_groups/Canaries")

    deployment_group = Repo.one!(from(d in DeploymentGroup, where: d.name == "Canaries"))
    assert deployment_group.notes == "Created for the summer campaign hardware batch"
  end

  test "notes is optional when creating a deployment group", %{conn: conn, org: org, product: product} do
    conn
    |> fill_in("Name", with: "Canaries")
    |> select("Platform", option: "platform")
    |> select("Architecture", option: "x86_64")
    |> select("Firmware", option: "1.0.0", exact_option: false)
    |> submit()
    |> assert_path(~p"/org/#{org}/#{product}/deployment_groups/Canaries")

    deployment_group = Repo.one!(from(d in DeploymentGroup, where: d.name == "Canaries"))
    assert deployment_group.notes == nil
  end

  describe "recover-form" do
    test "restores platform and architecture from form params", %{conn: conn} do
      conn
      |> unwrap(fn view ->
        render_change(view, "recover-form", %{
          "deployment_group" => %{
            "platform" => "platform",
            "architecture" => "x86_64"
          }
        })
      end)
      |> assert_has("select[name='deployment_group[architecture]'] option", text: "x86_64")
      |> assert_has("select[name='deployment_group[firmware]'] option", exact: false)
    end

    test "handles recover-form with no platform set (empty platform branch)", %{conn: conn} do
      conn
      |> unwrap(fn view ->
        render_change(view, "recover-form", %{
          "deployment_group" => %{
            "platform" => "",
            "architecture" => ""
          }
        })
      end)
      |> assert_has("h1", text: "Add Deployment Group")
    end
  end

  describe "firmware_dropdown_options with invalid semver" do
    test "page renders when a firmware has a non-semver version", %{
      conn: conn,
      org: org,
      product: product
    } do
      from(f in Firmware, where: f.product_id == ^product.id)
      |> Repo.update_all(set: [version: "not-valid-semver"])

      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/new")
      |> assert_has("h1", text: "Add Deployment Group")
      |> select("Platform", option: "platform")
      |> select("Architecture", option: "x86_64")
      |> assert_has("select[name='deployment_group[firmware]'] option", exact: false)
    end
  end

  describe "update-form platform and architecture events" do
    test "selecting platform loads architecture options", %{
      conn: conn,
      org: org,
      product: product
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/new")
      |> unwrap(fn view ->
        render_change(view, "update-form", %{
          "_target" => ["deployment_group", "platform"],
          "deployment_group" => %{"platform" => "platform"}
        })
      end)
      |> assert_has("option", text: "x86_64")
    end

    test "selecting architecture loads firmware options", %{
      conn: conn,
      org: org,
      product: product
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/new")
      |> unwrap(fn view ->
        render_change(view, "update-form", %{
          "_target" => ["deployment_group", "platform"],
          "deployment_group" => %{"platform" => "platform"}
        })
      end)
      |> unwrap(fn view ->
        render_change(view, "update-form", %{
          "_target" => ["deployment_group", "architecture"],
          "deployment_group" => %{"platform" => "platform", "architecture" => "x86_64"}
        })
      end)
      |> assert_has("option", text: "1.0.0", exact: false)
    end

    test "update-form for other fields is a noop", %{
      conn: conn,
      org: org,
      product: product
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/new")
      |> unwrap(fn view ->
        render_change(view, "update-form", %{
          "_target" => ["deployment_group", "name"],
          "deployment_group" => %{"name" => "some name"}
        })
      end)
      |> assert_has("h1", text: "Add Deployment Group")
    end
  end
end
