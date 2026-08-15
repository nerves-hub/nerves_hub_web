defmodule NervesHub.ManagedDeployments.InflightDeploymentCheckTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.ManagedDeployments.InflightDeploymentCheck

  test "schema fields are defined" do
    check = %InflightDeploymentCheck{}
    assert is_nil(check.device_id)
    assert is_nil(check.deployment_id)
  end
end
