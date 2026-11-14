defmodule NervesHub.Devices.VisibilityTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgRoles
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Visibility
  alias NervesHub.Fixtures

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    owner = Fixtures.user_fixture()
    org = Fixtures.org_fixture(owner)
    product = Fixtures.product_fixture(owner, org)
    org_key = Fixtures.org_key_fixture(org, owner, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    devices =
      for tags <- [["support"], ["support", "eu"], ["eu"], nil], into: %{} do
        device = Fixtures.device_fixture(org, product, firmware, %{tags: tags})
        {tags, device.identifier}
      end

    %{org: org, owner: owner, devices: devices, member: Fixtures.user_fixture()}
  end

  defp visible(user) do
    Device
    |> Visibility.where_visible(user)
    |> select([d], d.identifier)
    |> Repo.all()
    |> Enum.sort()
  end

  defp identifiers(devices, tag_lists), do: devices |> Map.take(tag_lists) |> Map.values() |> Enum.sort()

  defp give_role(org, user, params) do
    role = Fixtures.org_role_fixture(org, params)
    {:ok, _} = Accounts.add_org_user(org, user, %{org_role_id: role.id})
    role
  end

  test "a built-in role sees every device", %{org: org, member: member, devices: devices} do
    {:ok, _} = Accounts.add_org_user(org, member, %{role: :view})

    assert visible(member) == identifiers(devices, Map.keys(devices))
  end

  test "a custom role without tags sees every device", %{org: org, member: member, devices: devices} do
    give_role(org, member, %{})

    assert visible(member) == identifiers(devices, Map.keys(devices))
  end

  test "a role limited to tags sees the devices that have all of them", %{org: org, member: member, devices: devices} do
    give_role(org, member, %{device_tags: ["support", "eu"], device_tag_operator: :and})

    assert visible(member) == identifiers(devices, [["support", "eu"]])
  end

  test "a role limited to any of its tags sees the devices with one of them", %{
    org: org,
    member: member,
    devices: devices
  } do
    give_role(org, member, %{device_tags: ["support", "eu"], device_tag_operator: :or})

    assert visible(member) == identifiers(devices, [["support"], ["support", "eu"], ["eu"]])
  end

  test "follows the role as it is when the query runs", %{org: org, member: member, devices: devices} do
    role = give_role(org, member, %{device_tags: ["support"]})
    assert visible(member) == identifiers(devices, [["support"], ["support", "eu"]])

    {:ok, _} = OrgRoles.update_org_role(role, %{"device_tags" => ""})
    assert visible(member) == identifiers(devices, Map.keys(devices))
  end

  test "someone outside the org, or removed from it, sees nothing", %{org: org, member: member} do
    assert visible(member) == []

    {:ok, _} = Accounts.add_org_user(org, member, %{role: :admin})
    :ok = Accounts.remove_org_user(org, member)

    assert visible(member) == []
  end

  test "each org's role applies to that org's devices", %{org: org, member: member, devices: devices, tmp_dir: tmp_dir} do
    give_role(org, member, %{device_tags: ["eu"]})

    other_org = Fixtures.org_fixture(member)
    other_product = Fixtures.product_fixture(member, other_org)
    other_key = Fixtures.org_key_fixture(other_org, member, tmp_dir)
    other_firmware = Fixtures.firmware_fixture(other_key, other_product, %{dir: tmp_dir})
    untagged = Fixtures.device_fixture(other_org, other_product, other_firmware)

    assert visible(member) == Enum.sort([untagged.identifier | identifiers(devices, [["support", "eu"], ["eu"]])])
  end
end
