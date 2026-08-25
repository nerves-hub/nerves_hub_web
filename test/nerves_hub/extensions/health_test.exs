defmodule NervesHub.Extensions.HealthTest do
  @moduledoc """
  The pace at which a device is asked for health reports.

  Only this module asks. Everything below is about how it settles on how often,
  and about the asymmetry that makes it work: a page opening says so, a page
  closing says nothing and is noticed on the next check.
  """

  use ExUnit.Case, async: true

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Extensions.Health
  alias NervesHub.Extensions.PubSub
  alias NervesHub.Extensions.State

  # Both default to 60 in config, so the units are what tells the two timers
  # apart: a minute while watched, an hour while nobody is looking.
  @watched_ms to_timeout(minute: 1)
  @idle_ms to_timeout(hour: 1)

  setup do
    device_id = System.unique_integer([:positive])

    %{device_id: device_id, state: State.new(%DeviceInfo{device_id: device_id})}
  end

  describe "attaching" do
    test "asks straight away and settles into the platform interval", %{device_id: device_id, state: state} do
      {state, effects} = Health.attach(state)

      assert State.get(state, :mode) == :idle
      assert {:group_join, "device:health/#{device_id}"} in effects
      assert {:tick, :check} in effects
      assert {:start_timer, :check, first_ms, @idle_ms} = timer(effects)

      # Offset so a fleet attaching together does not answer together.
      assert first_ms in 1..@idle_ms
    end

    test "picks up a page that was already open", %{device_id: device_id, state: state} do
      :ok = PubSub.watch_health(device_id)

      {state, effects} = Health.attach(state)

      assert State.get(state, :mode) == :watched
      assert {:start_timer, :check, @watched_ms} = timer(effects)
    end

    test "detaching gives up the timer and the group", %{device_id: device_id, state: state} do
      {state, _effects} = Health.attach(state)

      {state, effects} = Health.detach(state)

      assert State.get(state, :mode) == nil
      assert {:cancel_timer, :check} in effects
      assert {:group_leave, "device:health/#{device_id}"} in effects
    end
  end

  describe "a page opening" do
    test "speeds the reporting up and asks now", %{state: state} do
      {state, _effects} = Health.attach(state)

      {state, effects} = Health.handle_info(:watching, state)

      assert State.get(state, :mode) == :watched
      assert {:tick, :check} in effects
      assert {:start_timer, :check, @watched_ms} = timer(effects)
    end

    test "a second page changes nothing", %{device_id: device_id, state: state} do
      :ok = PubSub.watch_health(device_id)
      {state, _effects} = Health.attach(state)

      # What the device would otherwise pay for every extra person looking at it.
      assert {state, []} = Health.handle_info(:watching, state)
      assert State.get(state, :mode) == :watched
    end
  end

  describe "checking" do
    test "asks the device, and nothing more while the pace is right", %{device_id: device_id, state: state} do
      :ok = PubSub.watch_health(device_id)
      {state, _effects} = Health.attach(state)

      assert {_state, [{:push, "health:check", %{}}]} = Health.handle_info(:check, state)
    end

    test "slows back down once the last page has closed", %{device_id: device_id, state: state} do
      watcher = watch_from_another_process(device_id)
      {state, _effects} = Health.attach(state)
      assert State.get(state, :mode) == :watched

      # Nothing announces this: the page is gone, and with it any chance of it
      # saying so. The next check is where that gets noticed.
      close(watcher, device_id)

      {state, effects} = Health.handle_info(:check, state)

      assert State.get(state, :mode) == :idle
      assert {:push, "health:check", %{}} in effects
      assert {:start_timer, :check, first_ms, @idle_ms} = timer(effects)
      assert first_ms in 1..@idle_ms
    end

    test "picks up a watcher whose announcement never arrived", %{device_id: device_id, state: state} do
      {state, _effects} = Health.attach(state)
      assert State.get(state, :mode) == :idle

      # A join this node had not replicated when the page announced itself would
      # leave the announcement landing nowhere. Reading membership on every
      # check means that heals, rather than lasting the life of the connection.
      :ok = PubSub.watch_health(device_id)

      {state, effects} = Health.handle_info(:check, state)

      assert State.get(state, :mode) == :watched
      assert {:start_timer, :check, @watched_ms} = timer(effects)
    end
  end

  defp timer(effects) do
    Enum.find(effects, &match?({:start_timer, :check, _}, &1)) ||
      Enum.find(effects, &match?({:start_timer, :check, _, _}, &1))
  end

  # A watcher the test can kill, since the test process itself cannot stand in
  # for a page that closes.
  defp watch_from_another_process(device_id) do
    test = self()

    pid =
      spawn(fn ->
        :ok = PubSub.watch_health(device_id)
        send(test, :watching)
        Process.sleep(:infinity)
      end)

    assert_receive :watching, 500
    pid
  end

  defp close(pid, device_id) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 500

    # Membership is given up by the group noticing the exit, not by the exit
    # itself, so the read has to wait for the group rather than the process.
    wait_until(fn -> not PubSub.health_watched?(device_id) end)
  end

  defp wait_until(fun, attempts \\ 50) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("the watcher never left the group")

      true ->
        Process.sleep(20)
        wait_until(fun, attempts - 1)
        # =======
        #   use NervesHub.DataCase, async: true

        #   alias NervesHub.DeviceLink.DeviceInfo
        #   alias NervesHub.Extensions.Health
        #   alias NervesHub.Extensions.State
        #   alias NervesHub.Fixtures

        #   setup do
        #     user = Fixtures.user_fixture()
        #     org = Fixtures.org_fixture(user)
        #     product = Fixtures.product_fixture(user, org)
        #     org_key = Fixtures.org_key_fixture(org, user)
        #     firmware = Fixtures.firmware_fixture(org_key, product)
        #     device = Fixtures.device_fixture(org, product, firmware)

        #     device_info = %DeviceInfo{
        #       device_id: device.id,
        #       device_identifier: device.identifier,
        #       org_id: org.id,
        #       product_id: product.id
        #     }

        #     state = State.new(device_info)
        #     %{state: state, device: device}
        #   end

        #   describe "description/0" do
        #     test "returns a non-empty string" do
        #       assert is_binary(Health.description())
        #       assert String.length(Health.description()) > 0
        #     end
        #   end

        #   describe "enabled?/0" do
        #     test "returns true" do
        #       assert Health.enabled?() == true
        #     end
        #   end

        #   describe "attach/1" do
        #     test "returns state and effects including a timer start and tick" do
        #       state = State.new(%DeviceInfo{device_id: 1, device_identifier: "x"})
        #       {new_state, effects} = Health.attach(state)

        #       assert new_state == state
        #       assert Enum.any?(effects, &match?({:tick, :check}, &1))
        #       assert Enum.any?(effects, &match?({:start_timer, :check, _}, &1))
        #     end
        #   end

        #   describe "detach/1" do
        #     test "returns state and a cancel_timer effect" do
        #       state = State.new(%DeviceInfo{device_id: 1, device_identifier: "x"})
        #       {new_state, effects} = Health.detach(state)

        #       assert new_state == state
        #       assert [{:cancel_timer, :check}] = effects
        #     end
        #   end

        #   describe "handle_info/2 :check" do
        #     test "pushes a health:check message" do
        #       state = State.new(%DeviceInfo{device_id: 1, device_identifier: "x"})
        #       {new_state, effects} = Health.handle_info(:check, state)

        #       assert new_state == state
        #       assert [{:push, "health:check", %{}}] = effects
        #     end
        #   end

        #   describe "handle_in/3 report" do
        #     test "saves health and metrics from a device report", %{state: state} do
        #       report = %{
        #         "value" => %{
        #           "metrics" => %{"cpu_temp" => 42.0, "load_1min" => 0.5},
        #           "alarms" => [],
        #           "metadata" => %{}
        #         }
        #       }

        #       {new_state, effects} = Health.handle_in("report", report, state)
        #       assert new_state == state
        #       assert effects == []
        #     end

        #     test "handles a report with no metrics key", %{state: state} do
        #       report = %{"value" => %{"alarms" => []}}

        #       {new_state, effects} = Health.handle_in("report", report, state)
        #       assert new_state == state
        #       assert effects == []
        #     end
        #   end

        #   describe "request_health_check/1" do
        #     test "broadcasts to device without raising", %{device: device} do
        #       assert :ok = Health.request_health_check(device)
        # >>>>>>> e631de8c (Add tests to cover the work that's been merged to main in the past week)
    end
  end
end
