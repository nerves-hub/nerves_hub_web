defmodule NervesHub.AuditLogs.AuditLogTest do
  use NervesHub.DataCase

  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Fixtures

  setup do
    Fixtures.standard_fixture()
  end

  describe "build" do
    test "includes changes if present", %{device: device, user: user} do
      params = %{tags: ["howdy"]}
      al = AuditLog.build(user, device, :update, "updated", params)
      assert al.changes == params
    end

    test "can use supplied description", %{device: device, user: user} do
      description = "what just happened?!"
      al = AuditLog.build(user, device, :update, description, %{})
      assert al.description == description
      assert al.params == %{}
    end
  end
end
