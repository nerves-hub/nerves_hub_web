defmodule NervesHub.Ash.Deployments.DeploymentGroupTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Deployments.DeploymentGroup
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
    test "get by id", %{deployment_group: dg} do
      found = DeploymentGroup.get!(dg.id)
      assert found.id == dg.id
      assert found.name == dg.name
    end

    test "list_by_product returns deployment groups", %{product: product, deployment_group: dg} do
      groups = DeploymentGroup.list_by_product!(product.id)
      assert Enum.any?(groups, &(&1.id == dg.id))
    end

    test "get_by_product_and_name returns group", %{product: product, deployment_group: dg} do
      found = DeploymentGroup.get_by_product_and_name!(product.id, dg.name)
      assert found.id == dg.id
    end
  end

  describe "updating_count" do
    test "returns count of inflight updates", %{deployment_group: dg} do
      count = DeploymentGroup.updating_count!(dg.id)
      assert is_integer(count)
      assert count >= 0
    end
  end

  describe "update" do
    test "updates deployment group name", %{deployment_group: dg} do
      ash_dg = DeploymentGroup.get!(dg.id)
      updated = DeploymentGroup.update!(ash_dg, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end
  end

  describe "get_device_count" do
    test "returns device count for deployment group", %{deployment_group: dg} do
      count = DeploymentGroup.get_device_count!(dg.id)
      assert is_integer(count)
      assert count >= 0
    end
  end

  describe "list_active" do
    test "returns active deployment groups", %{deployment_group: dg} do
      # Activate the deployment group first
      ash_dg = DeploymentGroup.get!(dg.id)
      DeploymentGroup.update!(ash_dg, %{is_active: true})

      active = DeploymentGroup.list_active!()
      assert Enum.any?(active, &(&1.id == dg.id))
    end

    test "excludes inactive deployment groups", %{deployment_group: dg} do
      # Deployment groups are inactive by default
      active = DeploymentGroup.list_active!()
      refute Enum.any?(active, &(&1.id == dg.id))
    end
  end

  describe "destroy" do
    test "deletes deployment group", %{deployment_group: dg} do
      ash_dg = DeploymentGroup.get!(dg.id)
      assert :ok = DeploymentGroup.destroy!(ash_dg)
    end
  end
end
