defmodule NervesHub.ManagedDeployments.DuplicateReleaseTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
    archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    %{
      user: user,
      firmware: firmware,
      next_firmware: next_firmware,
      archive: archive,
      deployment_group: deployment_group
    }
  end

  defp create_release(%{deployment_group: deployment_group, user: user}, firmware, archive) do
    ManagedDeployments.create_deployment_release(deployment_group, firmware, archive, user, %{})
  end

  test "refuses a release with the current release's firmware and archive", context do
    assert {:error, changeset} = create_release(context, context.firmware, nil)
    assert {"The current release already has this firmware and archive", _} = changeset.errors[:firmware]

    assert [_first_release] = ManagedDeployments.list_deployment_releases(context.deployment_group)
  end

  test "allows the current release's firmware with a different archive", context do
    assert {:ok, _} = create_release(context, context.firmware, context.archive)
    assert {:error, _} = create_release(context, context.firmware, context.archive)

    # Dropping the archive is a change too
    assert {:ok, _} = create_release(context, context.firmware, nil)
  end

  test "allows firmware from a release before the current one", context do
    assert {:ok, _} = create_release(context, context.next_firmware, nil)
    assert {:ok, _} = create_release(context, context.firmware, nil)
  end

  test "checks against the current release, not the one the caller last saw", context do
    assert {:ok, _} = create_release(context, context.next_firmware, nil)

    # `context.deployment_group` still has the first release as its current one
    assert {:error, _} = create_release(context, context.next_firmware, nil)
  end
end
