defmodule NervesHub.Extensions.PubSubTest do
  use ExUnit.Case, async: true

  alias NervesHub.Extensions.Health
  alias NervesHub.Extensions.PubSub
  alias Phoenix.Socket.Broadcast

  # Unique per test so concurrent tests don't share a group key or topic.
  setup do
    %{device_id: System.unique_integer([:positive])}
  end

  test "broadcast_to_device reaches the device-side extensions channel", %{
    device_id: device_id
  } do
    :ok = PubSub.subscribe_device(device_id)

    :ok = PubSub.broadcast_to_device(device_id, "health:check", %{})

    topic = "device:#{device_id}:extensions"
    assert_receive %Broadcast{topic: ^topic, event: "health:check", payload: %{}}, 500
  end

  test "broadcast_report reaches a report subscriber (the Show LiveView)", %{device_id: device_id} do
    :ok = PubSub.subscribe_reports(device_id)

    :ok = PubSub.broadcast_report(device_id, "health_check_report", %{})

    assert_receive %Broadcast{event: "health_check_report"}, 500
  end

  test "a report is NOT echoed to the device-side channel (self-exclusion via direction split)", %{
    device_id: device_id
  } do
    # The device-side channel subscribes to the web->device topic only.
    :ok = PubSub.subscribe_device(device_id)

    :ok = PubSub.broadcast_report(device_id, "health_check_report", %{})

    # It must not receive the report it (in production) originated — otherwise it
    # would push it straight back down to the device.
    refute_receive %Broadcast{event: "health_check_report"}, 200
  end

  test "a report subscriber does NOT receive web->device commands", %{
    device_id: device_id
  } do
    :ok = PubSub.subscribe_reports(device_id)

    :ok = PubSub.broadcast_to_device(device_id, "health:check", %{})

    refute_receive %Broadcast{event: "health:check"}, 200
  end

  test "the device-side subscription is node-local, so it is not a group member", %{
    device_id: device_id
  } do
    # The whole point of keeping web->device on Phoenix.PubSub: a connected
    # device must not put a cluster-replicated membership row on every node.
    :ok = PubSub.subscribe_device(device_id)

    assert Group.members(NervesHub.Group, "device:extensions/#{device_id}") == []
  end

  describe "health watchers" do
    test "watching announces itself to the device's extensions channel", %{device_id: device_id} do
      # Standing in for the extensions channel, which joins this group for as
      # long as the health extension is attached.
      :ok = Group.join(NervesHub.Group, PubSub.watch_key(device_id, :health), %{})

      task = Task.async(fn -> PubSub.watch(device_id, :health) end)
      :ok = Task.await(task)

      # Tagged with the module because that is how the channel routes it to the
      # extension that asked.
      assert_receive {Health, :watching}, 500
    end

    test "watching is also a standing membership, for the slowdown", %{device_id: device_id} do
      refute PubSub.watched?(device_id, :health)

      :ok = PubSub.watch(device_id, :health)

      assert PubSub.watched?(device_id, :health)
    end

    test "the page closing is what gives the membership up", %{device_id: device_id} do
      page = watching_page(device_id)
      assert PubSub.watched?(device_id, :health)

      # Nothing is sent on the way out -- a closed tab cannot -- so this is the
      # only thing that ends a watch.
      close(page)

      assert eventually(fn -> not PubSub.watched?(device_id, :health) end)
    end

    test "one page closing does not stop the others being watched", %{device_id: device_id} do
      page = watching_page(device_id)
      :ok = PubSub.watch(device_id, :health)

      close(page)

      # This test process is still a member, so the device keeps reporting at
      # the faster pace for whoever is left.
      assert PubSub.watched?(device_id, :health)
    end
  end

  # A watcher that can be closed, since the test process cannot stand in for a
  # page going away.
  defp watching_page(device_id) do
    test = self()

    pid =
      spawn(fn ->
        :ok = PubSub.watch(device_id, :health)
        send(test, :watching)
        Process.sleep(:infinity)
      end)

    assert_receive :watching, 500
    pid
  end

  defp close(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 500
  end

  # Membership is given up by the group noticing the exit, not by the exit
  # itself, so the read has to wait for the group rather than the process.
  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(20) && eventually(fun, attempts - 1)
    end
  end

  describe "product-wide events (Phoenix.PubSub)" do
    setup do
      %{product_id: System.unique_integer([:positive])}
    end

    test "broadcast_to_product reaches a subscribed device", %{product_id: product_id} do
      :ok = PubSub.subscribe_product(product_id)

      # broadcast_from! excludes the caller, so publish from another process.
      task = Task.async(fn -> PubSub.broadcast_to_product(product_id, "attach", %{"extensions" => ["health"]}) end)
      Task.await(task)

      topic = "product:#{product_id}:extensions"
      assert_receive %Broadcast{topic: ^topic, event: "attach", payload: %{"extensions" => ["health"]}}, 500
    end

    test "broadcast_to_product excludes the caller (self-exclusion preserved)", %{product_id: product_id} do
      :ok = PubSub.subscribe_product(product_id)

      :ok = PubSub.broadcast_to_product(product_id, "detach", %{"extensions" => ["health"]})

      refute_receive %Broadcast{event: "detach"}, 200
    end
  end
end
