defmodule NervesHub.Ash.Deployments.DeploymentReleaseTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Deployments.DeploymentRelease
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware)

    %{
      user: user,
      org: org,
      product: product,
      firmware: firmware,
      deployment_group: deployment_group
    }
  end

  describe "read" do
    test "list_by_deployment_group returns releases", %{deployment_group: dg} do
      releases = DeploymentRelease.list_by_deployment_group!(dg.id)
      assert is_list(releases)
    end
  end

  describe "create" do
    test "creates a deployment release", %{deployment_group: dg, firmware: firmware, user: user} do
      release =
        DeploymentRelease.create!(%{
          deployment_group_id: dg.id,
          firmware_id: firmware.id,
          created_by_id: user.id,
          number: 1
        })

      assert release.id
      assert release.deployment_group_id == dg.id
      assert release.firmware_id == firmware.id
    end
  end
end
