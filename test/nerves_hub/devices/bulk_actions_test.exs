defmodule NervesHub.Devices.BulkActionsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices.BulkActions
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  # A device's connection, and the orchestrator, re-read the device when told it
  # changed. Told while the change is still inside a transaction, they read the
  # old row. These tests record the bulk action's transactions and the events it
  # sends, in the order it did them, and check no event went out while one was
  # open.

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{is_active: true, user: user})

    devices =
      for _ <- 1..3 do
        Fixtures.device_fixture(org, product, firmware, %{
          deployment_id: deployment_group.id,
          update_mode: :off,
          updates_blocked_until: DateTime.add(DateTime.utc_now(:second), 1, :hour)
        })
      end

    ids = Enum.map(devices, & &1.id)

    for id <- ids do
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, DeviceEvents.topic(%Device{id: id}))
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device_socket:#{id}")
    end

    :ok = DeploymentOrchestratorEvents.subscribe(deployment_group)

    %{
      user: user,
      org: org,
      product: product,
      firmware: firmware,
      deployment_group: deployment_group,
      ids: ids,
      query: where(Device, [d], d.id in ^ids)
    }
  end

  describe "query-based bulk actions send device events only once the change is committed" do
    test "enable_updates_for_devices/2", %{query: query, user: user, ids: ids} do
      {result, events} = record(fn -> BulkActions.enable_updates_for_devices(query, user) end)

      assert result == %{ok: 3, error: 0}
      assert sent(events, "updated") == ids
      assert count(events, "device-updated") == 3
      assert sent_inside_transaction(events) == []
    end

    test "disable_updates_for_devices/2", %{query: query, user: user, ids: ids} do
      Repo.update_all(query, set: [update_mode: :automatic])

      {result, events} = record(fn -> BulkActions.disable_updates_for_devices(query, user) end)

      assert result == %{ok: 3, error: 0}
      assert sent(events, "updated") == ids
      assert sent_inside_transaction(events) == []
    end

    test "set_update_mode_for_devices/3", %{query: query, user: user, ids: ids} do
      {result, events} = record(fn -> BulkActions.set_update_mode_for_devices(query, :automatic, user) end)

      assert result == %{ok: 3, error: 0}
      assert sent(events, "updated") == ids
      assert count(events, "device-updated") == 3
      assert sent_inside_transaction(events) == []
    end

    test "set_managed_updates_allowed_for_devices/3", %{query: query, user: user, ids: ids} do
      {result, events} = record(fn -> BulkActions.set_managed_updates_allowed_for_devices(query, true, user) end)

      assert result == %{ok: 3, error: 0}
      assert sent(events, "updated") == ids
      assert sent_inside_transaction(events) == []
    end

    test "clear_penalty_box_for_devices/2", %{query: query, user: user, ids: ids} do
      {result, events} = record(fn -> BulkActions.clear_penalty_box_for_devices(query, user) end)

      assert result == %{ok: 3, error: 0}
      assert sent(events, "updated") == ids
      assert sent_inside_transaction(events) == []
    end

    test "tag_devices/3", %{query: query, user: user, ids: ids} do
      {result, events} = record(fn -> BulkActions.tag_devices(query, user, ["fresh"]) end)

      assert result == %{ok: 3, error: 0}
      assert sent(events, "updated") == ids
      assert sent_inside_transaction(events) == []
    end

    test "add_tags_to_devices/3", %{query: query, user: user, ids: ids} do
      {result, events} = record(fn -> BulkActions.add_tags_to_devices(query, user, ["fresh"]) end)

      assert result == %{ok: 3, error: 0}
      assert sent(events, "updated") == ids
      assert sent_inside_transaction(events) == []
    end

    test "remove_tags_from_devices/3", %{query: query, user: user, ids: ids} do
      {result, events} = record(fn -> BulkActions.remove_tags_from_devices(query, user, ["beta"]) end)

      assert result == %{ok: 3, error: 0}
      assert sent(events, "updated") == ids
      assert sent_inside_transaction(events) == []
    end

    test "move_many/3", %{query: query, user: user, org: org, ids: ids} do
      target_product = Fixtures.product_fixture(user, org)

      {result, events} = record(fn -> BulkActions.move_many(query, target_product, user) end)

      assert result == %{ok: 3, error: 0}
      assert sent(events, "disconnect") == ids
      assert sent_inside_transaction(events) == []
    end

    test "move_many_to_deployment_group/3", %{
      query: query,
      user: user,
      product: product,
      firmware: firmware,
      deployment_group: deployment_group,
      ids: ids
    } do
      other_group =
        Fixtures.deployment_group_fixture(firmware, %{name: "Other", is_active: true, user: user})

      Repo.update_all(query, set: [deployment_id: other_group.id])
      assert Repo.aggregate(where(Device, product_id: ^product.id, deployment_id: ^deployment_group.id), :count) == 0

      {result, events} =
        record(fn -> BulkActions.move_many_to_deployment_group(query, deployment_group, user) end)

      assert result == %{ok: 3, error: 0}
      assert sent(events, "updated") == ids
      assert count(events, "bulk-devices-added") == 1
      assert sent_inside_transaction(events) == []
    end

    test "remove_many_from_deployment_group/1", %{query: query, ids: ids} do
      {result, events} = record(fn -> BulkActions.remove_many_from_deployment_group(query) end)

      assert result == %{ok: 3, error: 0}
      assert sent(events, "deployment_updated") == ids
      assert sent_inside_transaction(events) == []
    end
  end

  test "a device that cannot be changed is counted, and the others are still changed", %{
    query: query,
    user: user,
    ids: [deleted_id | others]
  } do
    # A soft-deleted device refuses any update but undeleting it.
    Repo.update_all(where(Device, id: ^deleted_id), set: [deleted_at: DateTime.utc_now(:second)])

    {result, events} = record(fn -> BulkActions.set_managed_updates_allowed_for_devices(query, true, user) end)

    assert result == %{ok: 2, error: 1}
    assert sent(events, "updated") == others
    assert sent_inside_transaction(events) == []

    refute Repo.get!(Device, deleted_id).managed_updates_allowed
    assert Enum.all?(others, &Repo.get!(Device, &1).managed_updates_allowed)
  end

  # Runs `fun` and returns its result with every event it sent, each paired with
  # how many transactions this process had open at the time. The telemetry
  # handler and the broadcasts both send from this process to this process, so
  # the mailbox holds them in the order they happened.
  defp record(fun) do
    test_pid = self()
    handler_id = "bulk-actions-transactions-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:nerves_hub, :repo, :query],
      fn _event, _measurements, %{query: query}, _config ->
        if self() == test_pid and query in ["begin", "commit", "rollback"] do
          send(test_pid, {:transaction, query})
        end
      end,
      nil
    )

    result =
      try do
        fun.()
      after
        :telemetry.detach(handler_id)
      end

    {result, drain(0, [])}
  end

  defp drain(depth, events) do
    receive do
      {:transaction, "begin"} -> drain(depth + 1, events)
      {:transaction, _commit_or_rollback} -> drain(depth - 1, events)
      %Broadcast{} = broadcast -> drain(depth, [{broadcast, depth} | events])
    after
      0 -> Enum.reverse(events)
    end
  end

  defp sent(events, event) do
    events
    |> Enum.filter(fn {broadcast, _depth} -> broadcast.event == event end)
    |> Enum.map(fn {broadcast, _depth} -> topic_device_id(broadcast) end)
    |> Enum.sort()
  end

  defp count(events, event), do: Enum.count(events, fn {broadcast, _depth} -> broadcast.event == event end)

  defp sent_inside_transaction(events) do
    for {broadcast, depth} <- events, depth > 0, do: {broadcast.topic, broadcast.event}
  end

  defp topic_device_id(%Broadcast{topic: "device:" <> id}), do: String.to_integer(id)
  defp topic_device_id(%Broadcast{topic: "device_socket:" <> id}), do: String.to_integer(id)
end
