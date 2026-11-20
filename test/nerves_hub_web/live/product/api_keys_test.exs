defmodule NervesHubWeb.Live.Product.ApiKeysTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHub.Products.ApiKeys
  alias NervesHub.Repo

  defp keys_path(org, product), do: "/org/#{org.name}/#{product.name}/settings/api_keys"

  defp open_create_dialog(session) do
    session
    |> click_button("#create-api-key", "Create key")
    |> assert_has("#create-api-key-dialog h2", text: "Create an API key")
  end

  # The role picker is a button and a listbox, not a `<select>`, so that each
  # role can say what it allows.
  defp open_role_menu(session) do
    unwrap(session, fn view -> view |> element("#api-key-role") |> render_click() end)
  end

  defp pick_role(session, name) do
    session
    |> open_role_menu()
    |> within("#api-key-role-options", &click_button(&1, name))
  end

  # The dialog's Create key button sits in its footer, outside the form it
  # submits, which PhoenixTest can't click.
  defp submit_create(session) do
    unwrap(session, fn view -> view |> form("#api-key-form") |> render_submit() end)
  end

  describe "the page" do
    test "is a tab of the product's settings", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> click_link("API keys")
      |> assert_path(keys_path(org, product))
      |> assert_has("nav a[aria-current='page']", text: "API keys")
      |> assert_has("p", text: "There are no API keys yet.")
      |> refute_has("#read-only-notice")
      |> refute_has("#create-api-key-dialog")
    end

    test "counts the active keys on its tab", %{conn: conn, org: org, product: product, user: user} do
      {:ok, _active, _} = ApiKeys.create(product, user, %{"name" => "CI deploys", "role" => "manage"})
      {:ok, retired, _} = ApiKeys.create(product, user, %{"name" => "Old runner", "role" => "view"})
      {:ok, _} = ApiKeys.deactivate(product, user, retired.id)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("nav a", text: "API keys 1 active")
    end

    test "view-only members are told they can't create or deactivate", %{
      conn: conn,
      org: org,
      user: user,
      product: product
    } do
      {:ok, _} = Accounts.change_org_user_role(Accounts.get_org_user!(org, user.id), :view)

      conn
      |> visit(keys_path(org, product))
      |> assert_has("#read-only-notice", text: "can't create or deactivate them")
      |> refute_has("#create-api-key")
    end
  end

  describe "creating a key" do
    test "shows it once, and never again", %{conn: conn, org: org, product: product} do
      session =
        conn
        |> visit(keys_path(org, product))
        |> open_create_dialog()
        |> fill_in("Name", with: "CI deploys")
        |> pick_role("Manage")
        |> submit_create()
        |> assert_has("#new-api-key h2", text: "Copy the key for CI deploys")
        |> assert_has("#new-api-key", text: "This is the only time it is shown.")
        |> assert_has("#api-key-row-#{hd(ApiKeys.list(product)).id}", text: "Manage")
        |> assert_has("#new-api-key-note", text: "Manage · created just now")
        # Cancel, Escape or a click outside would throw the key away.
        |> refute_has("#new-api-key button", text: "Cancel")
        |> refute_has("#new-api-key-container[phx-click-away]")
        |> refute_has("#new-api-key-container[phx-window-keydown]")
        |> refute_has("#new-api-key button[aria-label='close']")

      [token] = Regex.run(~r/nhpk_[0-9A-Za-z]+/, render(session.view))

      assert {:ok, api_key} = ApiKeys.authenticate(token)
      assert api_key.name == "CI deploys"
      assert api_key.role == :manage

      # Dismissing the dialog is the only way out of it, and nothing on the
      # page can bring the key back.
      html =
        session
        |> within("#new-api-key", &click_button(&1, "I've copied it"))
        |> refute_has("#new-api-key")
        |> then(&render(&1.view))

      refute html =~ token

      html =
        conn
        |> visit(keys_path(org, product))
        |> refute_has("#new-api-key")
        |> then(&render(&1.view))

      refute html =~ token
    end

    test "says what each role allows", %{conn: conn, org: org, product: product} do
      _role = Fixtures.org_role_fixture(org, %{name: "Canary only", device_tags: ["canary"]})

      conn
      |> visit(keys_path(org, product))
      |> open_create_dialog()
      |> assert_has("#create-api-key-dialog", text: "Read this product's devices")
      |> open_role_menu()
      |> assert_has("#api-key-role-options", text: "Built-in roles")
      |> assert_has("#api-key-role-options", text: "Custom roles")
      |> assert_has("#api-key-role-options", text: "Devices tagged")
      |> within("#api-key-role-options", &click_button(&1, "Manage"))
      |> assert_has("#create-api-key-dialog", text: "Everything view can do")
      |> pick_role("Canary only")
      |> assert_has("#create-api-key-dialog", text: "Devices tagged")
    end

    test "can be given one of the org's custom roles", %{conn: conn, org: org, product: product} do
      role = Fixtures.org_role_fixture(org, %{name: "Deployer", permissions: ["deployment_group:update"]})

      conn
      |> visit(keys_path(org, product))
      |> open_create_dialog()
      |> fill_in("Name", with: "CI deploys")
      |> pick_role("Deployer")
      |> submit_create()
      |> assert_has("#new-api-key h2", text: "Copy the key for CI deploys")

      assert [api_key] = ApiKeys.list(product)
      assert api_key.org_role_id == role.id
    end

    test "needs a name, and keeps the picked role while it is fixed", %{conn: conn, org: org, product: product} do
      role = Fixtures.org_role_fixture(org, %{name: "Deployer", permissions: ["deployment_group:update"]})

      conn
      |> visit(keys_path(org, product))
      |> open_create_dialog()
      |> pick_role("Deployer")
      |> submit_create()
      |> assert_has("#api-key-form", text: "can't be blank")
      |> refute_has("#new-api-key")
      |> assert_has("#api-key-form input[name='api_key[role]'][value='custom:#{role.id}']")
      |> fill_in("Name", with: "CI deploys")
      |> submit_create()
      |> assert_has("#new-api-key h2", text: "Copy the key for CI deploys")

      assert [api_key] = ApiKeys.list(product)
      assert api_key.org_role_id == role.id
    end

    test "only offers roles that do no more than the member's own", %{
      conn: conn,
      org: org,
      product: product,
      user: user
    } do
      own_role =
        Fixtures.org_role_fixture(org, %{name: "Releaser", permissions: ["product:update", "deployment_group:update"]})

      _wider = Fixtures.org_role_fixture(org, %{name: "Rebooter", permissions: ["device:reboot"]})
      {:ok, _} = Accounts.change_org_user_role(Accounts.get_org_user!(org, user.id), own_role)

      conn
      |> visit(keys_path(org, product))
      |> open_create_dialog()
      # View includes running support scripts, which this role doesn't.
      |> assert_has("#api-key-role", text: "Releaser")
      |> open_role_menu()
      |> assert_has("#api-key-role-options [role='option']", text: "Releaser")
      |> refute_has("#api-key-role-options [role='option']", text: "View")
      |> refute_has("#api-key-role-options [role='option']", text: "Manage")
      |> refute_has("#api-key-role-options [role='option']", text: "Rebooter")
      |> refute_has("#api-key-role-options", text: "Built-in roles")
      # A forged pick is ignored, and a forged submit is refused.
      |> unwrap(&render_click(&1, "pick-role", %{"role" => "manage"}))
      |> assert_has("#api-key-form input[name='api_key[role]'][value='custom:#{own_role.id}']")
      |> unwrap(fn view ->
        view |> form("#api-key-form") |> render_submit(%{api_key: %{name: "CI deploys", role: "manage"}})
      end)
      |> assert_has("#api-key-form", text: "can do more than your own role")
      |> refute_has("#new-api-key")

      assert ApiKeys.list(product) == []
    end

    test "is not offered the admin role", %{conn: conn, org: org, product: product} do
      conn
      |> visit(keys_path(org, product))
      |> open_create_dialog()
      |> open_role_menu()
      |> assert_has("#api-key-role-options [role='option']", text: "View")
      |> assert_has("#api-key-role-options [role='option']", text: "Manage")
      |> refute_has("#api-key-role-options [role='option']", text: "Admin")
    end

    test "can be abandoned", %{conn: conn, org: org, product: product} do
      conn
      |> visit(keys_path(org, product))
      |> open_create_dialog()
      # Cancel, Escape and a click outside all run the dialog's own
      # data-cancel, which pushes the event below.
      |> assert_has("#create-api-key-dialog button", text: "Cancel")
      |> assert_has("#create-api-key-dialog-container[phx-click-away]")
      |> assert_has("#create-api-key-dialog[data-cancel]")
      |> unwrap(&render_click(&1, "cancel-dialog", %{}))
      |> refute_has("#create-api-key-dialog")

      assert ApiKeys.list(product) == []
    end
  end

  describe "deactivating a key" do
    test "asks first, then stops it working", %{conn: conn, org: org, product: product, user: user} do
      {:ok, api_key, token} = ApiKeys.create(product, user, %{"name" => "CI deploys", "role" => "manage"})

      conn
      |> visit(keys_path(org, product))
      |> within("#api-key-row-#{api_key.id}", &click_button(&1, "Deactivate"))
      |> assert_has("#deactivate-api-key h2", text: "Deactivate CI deploys?")
      |> assert_has("#deactivate-api-key", text: "It has never been used")
      |> within("#deactivate-api-key", &click_button(&1, "Deactivate key"))
      |> assert_has("div", text: "API key CI deploys has been deactivated.")
      |> refute_has("#deactivate-api-key")
      |> refute_has("button", text: "Deactivate")

      assert Repo.reload!(api_key).deactivated_at
      assert ApiKeys.authenticate(token) == :error
    end

    test "can be abandoned", %{conn: conn, org: org, product: product, user: user} do
      {:ok, api_key, _token} = ApiKeys.create(product, user, %{"name" => "CI deploys", "role" => "manage"})

      conn
      |> visit(keys_path(org, product))
      |> within("#api-key-row-#{api_key.id}", &click_button(&1, "Deactivate"))
      |> assert_has("#deactivate-api-key button", text: "Cancel")
      |> unwrap(&render_click(&1, "cancel-dialog", %{}))
      |> refute_has("#deactivate-api-key")

      refute Repo.reload!(api_key).deactivated_at
    end

    test "is refused for a view-only member", %{conn: conn, org: org, product: product, user: user} do
      {:ok, api_key, _token} = ApiKeys.create(product, user, %{"name" => "CI deploys", "role" => "manage"})
      {:ok, _} = Accounts.change_org_user_role(Accounts.get_org_user!(org, user.id), :view)

      session =
        conn
        |> visit(keys_path(org, product))
        |> assert_has("#api-key-row-#{api_key.id}", text: "CI deploys")
        |> refute_has("button", text: "Deactivate")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(session.view, "deactivate", %{"id" => api_key.id}))

      refute Repo.reload!(api_key).deactivated_at
    end
  end
end
