defmodule NervesHub.ErrorReports.GroupBufferTest do
  # Not async: the buffer flushes from processes other than the test, which
  # needs the sandbox in shared mode.
  use NervesHub.DataCase, async: false

  import Ecto.Query

  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.ErrorReports.GroupBuffer
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    # A long delay so nothing flushes on its own; every test flushes explicitly.
    name = :"group_buffer_#{System.unique_integer([:positive])}"
    {:ok, _pid} = start_supervised({GroupBuffer, name: name, max_delay: to_timeout(minute: 5)})

    %{product: product, buffer: name, user: user}
  end

  defp entry(product, overrides \\ %{}) do
    at = Map.get(overrides, :at, ~U[2026-08-31 10:00:00.000000Z])

    %{
      product_id: product.id,
      fingerprint: Map.get(overrides, :fingerprint, "fp-one"),
      fingerprint_version: 1,
      kind: "error",
      source: "logger",
      reason: Map.get(overrides, :reason, "** (RuntimeError) boom"),
      frames: Map.get(overrides, :frames, [%{module: "M", function: "f/1", file: "m.ex", line: 4}]),
      timestamp: at,
      firmware_uuid: Map.get(overrides, :firmware_uuid, "fw-1")
    }
  end

  defp group(product) do
    Repo.one(from(g in ErrorGroup, where: g.product_id == ^product.id))
  end

  describe "coalescing" do
    test "many occurrences of one error become one row", %{product: product, buffer: buffer} do
      for i <- 1..50 do
        at = DateTime.add(~U[2026-08-31 10:00:00.000000Z], i, :second)
        GroupBuffer.record(buffer, entry(product, %{at: at, firmware_uuid: "fw-#{i}"}))
      end

      :ok = GroupBuffer.flush(buffer)

      assert %ErrorGroup{} = group = group(product)
      assert group.occurrence_count == 50
      assert group.first_seen_at == ~U[2026-08-31 10:00:01.000000Z]
      assert group.last_seen_at == ~U[2026-08-31 10:00:50.000000Z]
      assert group.first_seen_firmware_uuid == "fw-1"
      assert group.last_seen_firmware_uuid == "fw-50"
    end

    test "different fingerprints stay apart", %{product: product, buffer: buffer} do
      GroupBuffer.record(buffer, entry(product, %{fingerprint: "fp-one"}))
      GroupBuffer.record(buffer, entry(product, %{fingerprint: "fp-two"}))
      :ok = GroupBuffer.flush(buffer)

      assert Repo.aggregate(from(g in ErrorGroup, where: g.product_id == ^product.id), :count) == 2
    end

    test "the top frame is denormalised onto the group", %{product: product, buffer: buffer} do
      GroupBuffer.record(buffer, entry(product))
      :ok = GroupBuffer.flush(buffer)

      group = group(product)
      assert group.top_frame_module == "M"
      assert group.top_frame_function == "f/1"
      assert group.top_frame_file == "m.ex"
      assert group.top_frame_line == 4
    end

    test "an error with no frames still records a group", %{product: product, buffer: buffer} do
      GroupBuffer.record(buffer, entry(product, %{frames: []}))
      :ok = GroupBuffer.flush(buffer)

      assert %ErrorGroup{top_frame_module: nil, occurrence_count: 1} = group(product)
    end

    test "counts accumulate across flushes", %{product: product, buffer: buffer} do
      GroupBuffer.record(buffer, entry(product))
      :ok = GroupBuffer.flush(buffer)

      GroupBuffer.record(buffer, entry(product))
      :ok = GroupBuffer.flush(buffer)

      assert %ErrorGroup{occurrence_count: 2} = group(product)
    end

    test "flushing an empty buffer writes nothing", %{product: product, buffer: buffer} do
      :ok = GroupBuffer.flush(buffer)

      assert group(product) == nil
    end
  end

  describe "out-of-order occurrences" do
    setup %{product: product, buffer: buffer} do
      GroupBuffer.record(buffer, entry(product, %{at: ~U[2026-08-31 10:00:00.000000Z], firmware_uuid: "fw-now"}))
      :ok = GroupBuffer.flush(buffer)
      :ok
    end

    test "an older occurrence moves first_seen back, not last_seen", %{product: product, buffer: buffer} do
      GroupBuffer.record(buffer, entry(product, %{at: ~U[2020-01-01 00:00:00.000000Z], firmware_uuid: "fw-old"}))
      :ok = GroupBuffer.flush(buffer)

      group = group(product)
      assert group.first_seen_at == ~U[2020-01-01 00:00:00.000000Z]
      assert group.first_seen_firmware_uuid == "fw-old"
      assert group.last_seen_at == ~U[2026-08-31 10:00:00.000000Z]
      assert group.last_seen_firmware_uuid == "fw-now"
      assert group.occurrence_count == 2
    end

    test "a newer occurrence moves last_seen forward", %{product: product, buffer: buffer} do
      GroupBuffer.record(buffer, entry(product, %{at: ~U[2026-09-01 00:00:00.000000Z], firmware_uuid: "fw-next"}))
      :ok = GroupBuffer.flush(buffer)

      group = group(product)
      assert group.last_seen_at == ~U[2026-09-01 00:00:00.000000Z]
      assert group.last_seen_firmware_uuid == "fw-next"
      assert group.first_seen_at == ~U[2026-08-31 10:00:00.000000Z]
    end

    test "an out-of-order batch coalesces to the right ends before writing", %{product: product, buffer: buffer} do
      GroupBuffer.record(buffer, entry(product, %{at: ~U[2026-09-02 00:00:00.000000Z], firmware_uuid: "fw-late"}))
      GroupBuffer.record(buffer, entry(product, %{at: ~U[2019-01-01 00:00:00.000000Z], firmware_uuid: "fw-early"}))
      :ok = GroupBuffer.flush(buffer)

      group = group(product)
      assert group.first_seen_firmware_uuid == "fw-early"
      assert group.last_seen_firmware_uuid == "fw-late"
      assert group.occurrence_count == 3
    end
  end

  describe "reopening" do
    setup %{product: product, buffer: buffer, user: user} do
      GroupBuffer.record(buffer, entry(product))
      :ok = GroupBuffer.flush(buffer)

      %{group: group(product), user: user}
    end

    test "a resolved group that happens again is reopened and marked regressed", %{
      product: product,
      buffer: buffer,
      group: group,
      user: user
    } do
      {:ok, _resolved} = group |> ErrorGroup.resolve_changeset(user) |> Repo.update()

      GroupBuffer.record(buffer, entry(product, %{at: ~U[2026-09-01 00:00:00.000000Z]}))
      :ok = GroupBuffer.flush(buffer)

      reopened = group(product)
      assert reopened.status == :unresolved
      assert reopened.regressed_at == ~U[2026-09-01 00:00:00.000000Z]
      assert reopened.occurrence_count == 2
    end

    test "a muted group keeps counting and stays muted", %{
      product: product,
      buffer: buffer,
      group: group,
      user: user
    } do
      {:ok, _muted} = group |> ErrorGroup.mute_changeset(user) |> Repo.update()

      GroupBuffer.record(buffer, entry(product, %{at: ~U[2026-09-01 00:00:00.000000Z]}))
      :ok = GroupBuffer.flush(buffer)

      still_muted = group(product)
      assert still_muted.status == :muted
      assert still_muted.regressed_at == nil
      assert still_muted.occurrence_count == 2
    end

    test "an unresolved group is not marked as regressed", %{product: product, buffer: buffer} do
      GroupBuffer.record(buffer, entry(product, %{at: ~U[2026-09-01 00:00:00.000000Z]}))
      :ok = GroupBuffer.flush(buffer)

      assert %ErrorGroup{status: :unresolved, regressed_at: nil} = group(product)
    end
  end

  describe "flushing on size" do
    test "a full batch is written without waiting for the delay", %{product: product} do
      name = :"group_buffer_size_#{System.unique_integer([:positive])}"

      {:ok, _pid} =
        start_supervised({GroupBuffer, name: name, max_batch_size: 3, max_delay: to_timeout(minute: 5)})

      for i <- 1..3, do: GroupBuffer.record(name, entry(product, %{fingerprint: "fp-#{i}"}))

      # `flush/2` waits for the in-flight write the third record kicked off.
      :ok = GroupBuffer.flush(name)

      assert Repo.aggregate(from(g in ErrorGroup, where: g.product_id == ^product.id), :count) == 3
    end
  end
end
