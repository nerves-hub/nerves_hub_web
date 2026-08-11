defmodule NervesHubWeb.Components.CommandPaletteTest do
  use NervesHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHubWeb.Components.CommandPalette
  alias Phoenix.LiveView.AsyncResult

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware, %{identifier: "palette-render-device"})

    # Reload the user so orgs/products are preloaded the way the app assigns them.
    user = Accounts.get_user_with_all_orgs_and_products(user.id)

    %{user: user, org: org, product: product, device: device}
  end

  test "renders the search input and product commands in a product scope", %{
    user: user,
    org: org,
    product: product,
    device: device
  } do
    scope = Scope.for_user(user) |> Scope.put_org(org) |> Scope.put_product(product)

    results =
      AsyncResult.ok(%{
        devices: [%{identifier: device.identifier, org_name: org.name, product_name: product.name}],
        deployment_groups: [],
        firmware: []
      })

    html =
      render_component(CommandPalette,
        id: "command-palette",
        current_scope: scope,
        query: "devices",
        results: results
      )

    assert html =~ "data-palette-input"
    # Static product navigation command is present and links correctly.
    assert html =~ ~s|href="/org/#{org.name}/#{product.name}/devices"|
    # A matching device is rendered as a deep link.
    assert html =~ ~s|href="/org/#{org.name}/#{product.name}/devices/#{device.identifier}"|
  end

  test "renders org-level commands and no product commands in an org scope", %{
    user: user,
    org: org,
    product: product
  } do
    scope = Scope.for_user(user) |> Scope.put_org(org)

    html =
      render_component(CommandPalette, id: "command-palette", current_scope: scope, query: "settings")

    assert html =~ ~s|href="/org/#{org.name}/settings"|
    refute html =~ ~s|href="/org/#{org.name}/#{product.name}/settings"|
  end
end
