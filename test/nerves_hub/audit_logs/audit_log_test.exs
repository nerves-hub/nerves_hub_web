defmodule NervesHub.AuditLogs.AuditLogTest do
  use NervesHub.DataCase, async: true

  import Ecto.Changeset, only: [get_change: 2]

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

  describe "changeset" do
    test "leaves a description at the limit alone", %{device: device, user: user} do
      description = String.duplicate("a", 500)

      changeset =
        AuditLog.build(user, device, description)
        |> AuditLog.changeset()

      assert get_change(changeset, :description) == description
    end

    test "truncates a description over the limit", %{device: device, user: user} do
      changeset =
        AuditLog.build(user, device, String.duplicate("a", 501))
        |> AuditLog.changeset()

      truncated = get_change(changeset, :description)

      assert String.length(truncated) == 500
      assert String.ends_with?(truncated, "…")
    end

    test "truncation counts graphemes, not bytes", %{device: device, user: user} do
      changeset =
        AuditLog.build(user, device, String.duplicate("日", 600))
        |> AuditLog.changeset()

      truncated = get_change(changeset, :description)

      assert String.length(truncated) == 500
      assert String.valid?(truncated)
    end
  end

  describe "changeset/2" do
    test "accepts keyword list params", %{device: device, user: user} do
      al = AuditLog.build(user, device, "something happened")
      params = Map.to_list(Map.from_struct(al)) |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      changeset = AuditLog.changeset(%AuditLog{}, params)
      assert changeset.valid?
    end
  end
end
