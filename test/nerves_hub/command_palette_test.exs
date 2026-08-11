defmodule NervesHub.CommandPaletteTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts.Scope
  alias NervesHub.CommandPalette
  alias NervesHub.Devices
  alias NervesHub.Fixtures

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    device = Fixtures.device_fixture(org, product, firmware, %{identifier: "palettesearch-alpha-1"})

    deployment_group =
      Fixtures.deployment_group_fixture(firmware, %{name: "palettesearch-rollout", user: user})

    # A second org the user does NOT belong to, with a device whose identifier
    # also matches "palettesearch-alpha" so we can assert it never leaks.
    other_user = Fixtures.user_fixture()
    other_org = Fixtures.org_fixture(other_user)
    other_product = Fixtures.product_fixture(other_user, other_org)
    other_org_key = Fixtures.org_key_fixture(other_org, other_user, tmp_dir)
    other_firmware = Fixtures.firmware_fixture(other_org_key, other_product, %{dir: tmp_dir})

    _foreign_device =
      Fixtures.device_fixture(other_org, other_product, other_firmware, %{
        identifier: "palettesearch-alpha-foreign"
      })

    %{
      user: user,
      org: org,
      product: product,
      firmware: firmware,
      device: device,
      deployment_group: deployment_group
    }
  end

  describe "search/3 scope bands" do
    test "product scope only searches the current product", %{user: user, org: org, product: product} do
      scope = Scope.for_user(user) |> Scope.put_org(org) |> Scope.put_product(product)

      results = CommandPalette.search(scope, "palettesearch-alpha")

      assert Enum.map(results.devices, & &1.identifier) == ["palettesearch-alpha-1"]
    end

    test "org scope searches all of the user's products in the org, never other orgs",
         %{user: user, org: org, product: product, firmware: firmware, tmp_dir: tmp_dir} do
      # A second product in the same org, with its own matching device.
      product2 = Fixtures.product_fixture(user, org)
      org_key2 = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware2 = Fixtures.firmware_fixture(org_key2, product2, %{dir: tmp_dir})

      Fixtures.device_fixture(org, product2, firmware2, %{identifier: "palettesearch-alpha-2"})
      _ = {product, firmware}

      scope = Scope.for_user(user) |> Scope.put_org(org)

      results = CommandPalette.search(scope, "palettesearch-alpha")

      identifiers = Enum.map(results.devices, & &1.identifier)
      assert "palettesearch-alpha-1" in identifiers
      assert "palettesearch-alpha-2" in identifiers
      refute "palettesearch-alpha-foreign" in identifiers
    end

    test "dashboard scope searches every product the user belongs to, never other orgs",
         %{user: user} do
      scope = Scope.for_user(user)

      results = CommandPalette.search(scope, "palettesearch-alpha")

      identifiers = Enum.map(results.devices, & &1.identifier)
      assert "palettesearch-alpha-1" in identifiers
      refute "palettesearch-alpha-foreign" in identifiers
    end
  end

  describe "search/3 entity types" do
    test "finds deployment groups by name substring", %{user: user, org: org} do
      scope = Scope.for_user(user) |> Scope.put_org(org)

      results = CommandPalette.search(scope, "palettesearch-rollout")

      assert Enum.map(results.deployment_groups, & &1.name) == ["palettesearch-rollout"]
    end

    test "finds firmware by uuid prefix", %{user: user, org: org, firmware: firmware} do
      scope = Scope.for_user(user) |> Scope.put_org(org)

      prefix = String.slice(firmware.uuid, 0, 8)
      results = CommandPalette.search(scope, prefix)

      assert Enum.any?(results.firmware, &(&1.uuid == firmware.uuid))
    end
  end

  describe "search/3 guards" do
    test "excludes soft-deleted devices", %{user: user, org: org, device: device} do
      {:ok, _} = Devices.delete_device(device)
      scope = Scope.for_user(user) |> Scope.put_org(org)

      results = CommandPalette.search(scope, "palettesearch-alpha")

      assert results.devices == []
    end

    test "returns empty results for terms shorter than two characters", %{user: user, org: org} do
      scope = Scope.for_user(user) |> Scope.put_org(org)

      assert CommandPalette.search(scope, "a") ==
               %{devices: [], deployment_groups: [], firmware: []}

      assert CommandPalette.search(scope, "   ") ==
               %{devices: [], deployment_groups: [], firmware: []}
    end
  end
end
