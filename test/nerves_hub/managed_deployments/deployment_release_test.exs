defmodule NervesHub.ManagedDeployments.DeploymentReleaseTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments.DeploymentRelease

  describe "new_changeset/5" do
    setup %{tmp_dir: tmp_dir} do
      Fixtures.standard_fixture(tmp_dir)
    end

    test "user not associated with product gets invalid created_by error", %{
      deployment_group: deployment_group,
      firmware: firmware
    } do
      unrelated_user = Fixtures.user_fixture()

      changeset = DeploymentRelease.new_changeset(deployment_group, firmware, nil, %{}, unrelated_user)

      refute changeset.valid?
      assert {:created_by, {"invalid associated user", []}} in changeset.errors
    end
  end
end
