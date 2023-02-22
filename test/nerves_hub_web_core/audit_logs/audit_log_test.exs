defmodule NervesHubWebCore.AuditLogs.AuditLogTest do
  use NervesHubWebCore.DataCase

  alias NervesHubWebCore.AuditLogs.AuditLog
  alias NervesHubWebCore.Fixtures

  setup do
    Fixtures.standard_fixture()
  end

  describe "build" do
    test "includes changes if present", %{device: device, user: user} do
      params = %{tags: ["howdy"]}
      al = AuditLog.build(user, device, :update, "updated", params)
      assert al.changes == params
    end

    test "adds firmware_uuid for device update messages", %{
      deployment: deployment,
      device: device
    } do
      deployment = Repo.preload(deployment, :firmware)

      al =
        AuditLog.build(deployment, device, :update, "firmware uuid", %{send_update_message: true})

      assert al.params.firmware_uuid == deployment.firmware.uuid
    end

    test "can use supplied description", %{device: device, user: user} do
      description = "what just happened?!"
      al = AuditLog.build(user, device, :update, description, %{})
      assert al.description == description
      assert al.params == %{}
    end
  end
end
