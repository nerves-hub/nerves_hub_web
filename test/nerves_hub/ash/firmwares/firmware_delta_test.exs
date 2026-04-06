defmodule NervesHub.Ash.Firmwares.FirmwareDeltaTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Firmwares.FirmwareDelta
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    source = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.1.0"})
    delta = Fixtures.firmware_delta_fixture(source, target)

    %{source: source, target: target, delta: delta}
  end

  describe "read" do
    test "list_by_source returns deltas", %{source: source, delta: delta} do
      deltas = FirmwareDelta.list_by_source!(source.id)
      assert Enum.any?(deltas, &(&1.id == delta.id))
    end

    test "list_by_target returns deltas", %{target: target, delta: delta} do
      deltas = FirmwareDelta.list_by_target!(target.id)
      assert Enum.any?(deltas, &(&1.id == delta.id))
    end

    test "get_by_source_and_target returns delta", %{source: source, target: target, delta: delta} do
      found = FirmwareDelta.get_by_source_and_target!(source.id, target.id)
      assert found.id == delta.id
    end
  end

  describe "update" do
    test "updates status", %{delta: delta} do
      ash_delta = FirmwareDelta.get!(delta.id)
      updated = FirmwareDelta.update!(ash_delta, %{status: :failed})
      assert updated.status == :failed
    end
  end

  describe "fail" do
    test "marks delta as failed", %{delta: delta} do
      ash_delta = FirmwareDelta.get!(delta.id)
      failed = FirmwareDelta.fail!(ash_delta)
      assert failed.status == :failed
    end
  end

  describe "time_out" do
    test "marks delta as timed out", %{delta: delta} do
      ash_delta = FirmwareDelta.get!(delta.id)
      timed_out = FirmwareDelta.time_out!(ash_delta)
      assert timed_out.status == :timed_out
    end
  end
end
