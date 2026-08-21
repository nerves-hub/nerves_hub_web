defmodule NervesHubWeb.Live.CommandPaletteTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  # The palette lives in the authenticated layout and is opened by the
  # CommandPalette JS hook (Cmd+K), which a PhoenixTest session can't press.
  # Opening only toggles a CSS class though — the search box, results and links
  # are always in the DOM — so we drive the real behaviour (type a query, get
  # scoped results with the correct destination) straight through the form,
  # which is what actually matters. We land on the deployment groups page
  # because it renders the sidebar layout and has no async loading to race.
  @label "Search devices, deployment groups, firmware"

  defp deployment_groups_path(org, product), do: "/org/#{org.name}/#{product.name}/deployment_groups"

  # Results are loaded via assign_async, so wait for the async assign to resolve
  # before asserting on them.
  defp await_results(session) do
    unwrap(session, fn view -> render_async(view) end)
  end

  test "is present in the authenticated layout", %{conn: conn, org: org, product: product} do
    conn
    |> visit(deployment_groups_path(org, product))
    |> assert_has("#command-palette [data-palette-input]")
  end

  test "surfaces a matching device linking to its page", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    href = "/org/#{org.name}/#{product.name}/devices/#{device.identifier}"

    conn
    |> visit(deployment_groups_path(org, product))
    |> fill_in(@label, with: device.identifier)
    |> await_results()
    |> assert_has(~s|#command-palette-results a[href="#{href}"]|, text: device.identifier)
  end

  test "surfaces a matching deployment group linking to its page", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    href = "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.id}"

    conn
    |> visit(deployment_groups_path(org, product))
    |> fill_in(@label, with: deployment_group.name)
    |> await_results()
    |> assert_has(~s|#command-palette-results a[href="#{href}"]|, text: deployment_group.name)
  end

  test "surfaces matching firmware linking to its page", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware
  } do
    href = "/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}"

    conn
    |> visit(deployment_groups_path(org, product))
    |> fill_in(@label, with: firmware.uuid)
    |> await_results()
    |> assert_has(~s|#command-palette-results a[href="#{href}"]|, text: firmware.uuid)
  end

  test "offers static navigation commands and navigates on click", %{
    conn: conn,
    org: org,
    product: product
  } do
    conn
    |> visit(deployment_groups_path(org, product))
    |> fill_in(@label, with: "Firmware")
    |> await_results()
    |> within("#command-palette-results", fn session ->
      click_link(session, "Firmware")
    end)
    |> assert_path("/org/#{org.name}/#{product.name}/firmware")
  end

  test "does not surface results from other organizations", %{
    conn: conn,
    org: org,
    product: product,
    tmp_dir: tmp_dir
  } do
    # A device in a different org the logged-in user is not a member of.
    other_user = Fixtures.user_fixture()
    other_org = Fixtures.org_fixture(other_user)
    other_product = Fixtures.product_fixture(other_user, other_org)
    other_org_key = Fixtures.org_key_fixture(other_org, other_user, tmp_dir)
    other_firmware = Fixtures.firmware_fixture(other_org_key, other_product, %{dir: tmp_dir})

    foreign =
      Fixtures.device_fixture(other_org, other_product, other_firmware, %{
        identifier: "palette-foreign-device"
      })

    conn
    |> visit(deployment_groups_path(org, product))
    |> fill_in(@label, with: foreign.identifier)
    |> await_results()
    |> refute_has("#command-palette-results a", text: foreign.identifier)
  end
end
