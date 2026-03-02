defmodule NervesHub.AuditLogs.AuditLogTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    Fixtures.standard_fixture(tmp_dir)
  end

  describe "build" do
    test "can use supplied description", %{device: device, user: user} do
      description = "what just happened?!"
      al = AuditLog.build(user, device, description)
      assert al.description == description
    end
  end
end
