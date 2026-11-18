defmodule NervesHubWeb.Live.Product.ApiKeysTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHub.Products.ApiKeys
  alias NervesHub.Repo

  defp keys_path(org, product), do: "/org/#{org.name}/#{product.name}/settings/api_keys"

  describe "the page" do
    test "is a tab of the product's settings", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> click_link("API keys")
      |> assert_path(keys_path(org, product))
      |> assert_has("nav a[aria-current='page']", text: "API keys")
      |> assert_has("p", text: "There are no API keys yet.")
      |> refute_has("#read-only-notice")
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
      |> refute_has("#api-key-form")
    end
  end

  describe "creating a key" do
    test "shows it once, and never again", %{conn: conn, org: org, product: product} do
      session =
        conn
        |> visit(keys_path(org, product))
        |> fill_in("Name", with: "CI deploys")
        |> select("Role", option: "Manage")
        |> click_button("Create key")
        |> assert_has("#new-api-key", text: "Copy the key for CI deploys")
        |> assert_has("#api-key-row-#{hd(ApiKeys.list(product)).id}", text: "Manage")

      [token] = Regex.run(~r/nhpk_[0-9A-Za-z]+/, render(session.view))

      assert {:ok, api_key} = ApiKeys.authenticate(token)
      assert api_key.name == "CI deploys"
      assert api_key.role == :manage

      # Gone once the page is left, and nothing on the page can bring it back.
      html =
        conn
        |> visit(keys_path(org, product))
        |> refute_has("#new-api-key")
        |> then(&render(&1.view))

      refute html =~ token
    end

    test "can be given one of the org's custom roles", %{conn: conn, org: org, product: product} do
      role = Fixtures.org_role_fixture(org, %{name: "Deployer", permissions: ["deployment_group:update"]})

      conn
      |> visit(keys_path(org, product))
      |> fill_in("Name", with: "CI deploys")
      |> select("Role", option: "Deployer")
      |> click_button("Create key")
      |> assert_has("#new-api-key", text: "Copy the key for CI deploys")

      assert [api_key] = ApiKeys.list(product)
      assert api_key.org_role_id == role.id
    end

    test "needs a name", %{conn: conn, org: org, product: product} do
      conn
      |> visit(keys_path(org, product))
      |> click_button("Create key")
      |> assert_has("#api-key-form", text: "can't be blank")
      |> refute_has("#new-api-key")

      assert ApiKeys.list(product) == []
    end

    test "is not offered the admin role", %{conn: conn, org: org, product: product} do
      conn
      |> visit(keys_path(org, product))
      |> assert_has("#api-key-form option", text: "View")
      |> assert_has("#api-key-form option", text: "Manage")
      |> refute_has("#api-key-form option", text: "Admin")
    end
  end

  describe "deactivating a key" do
    test "stops it working", %{conn: conn, org: org, product: product, user: user} do
      {:ok, api_key, token} = ApiKeys.create(product, user, %{"name" => "CI deploys", "role" => "manage"})

      conn
      |> visit(keys_path(org, product))
      |> click_button("Deactivate")
      |> assert_has("div", text: "API key CI deploys has been deactivated.")
      |> refute_has("button", text: "Deactivate")

      assert Repo.reload!(api_key).deactivated_at
      assert ApiKeys.authenticate(token) == :error
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
