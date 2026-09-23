defmodule NervesHub.Extensions.AlarmsTest do
  @moduledoc """
  The alarms extension: events as they happen, a snapshot to reconcile, and
  what the platform does when it has to drop an event.

  Storage is `NervesHub.Devices.AlarmsTest`'s subject; this is about the
  protocol around it.
  """

  use NervesHub.DataCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Alarms, as: Store
  alias NervesHub.Devices.DeviceAlarm
  alias NervesHub.Devices.DeviceAlarmHistory
  alias NervesHub.Extensions.Alarms
  alias NervesHub.Extensions.PubSub
  alias NervesHub.Extensions.State
  alias NervesHub.Fixtures
  alias Phoenix.Socket.Broadcast

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }

    AnalyticsRepo.query!("TRUNCATE TABLE device_alarm_history")
    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_alarm_history") end)

    %{device: device, state: State.new(device_info)}
  end

  describe "attaching" do
    test "asks for the whole set straight away, and sets no timer", %{state: state} do
      {_state, effects} = Alarms.attach(state)

      assert effects == [{:push, "alarms:sync", %{}}]
    end

    test "detaching gives up a pending resync", %{state: state} do
      {state, _effects} = Alarms.attach(state)

      {state, effects} = Alarms.detach(state)

      assert {:cancel_timer, :resync} in effects
      refute State.get(state, :resync_pending)
    end
  end

  describe "events" do
    test "a raise is stored, and recorded as history", %{device: device, state: state} do
      {^state, []} =
        Alarms.handle_in("raised", %{"alarm" => "Elixir.MyApp.HighTemp", "description" => "too hot"}, state)

      assert Store.current_alarms_for_device(device) == [{"MyApp.HighTemp", "too hot"}]
      assert [%{alarm: "MyApp.HighTemp", event: "raised", description: "too hot"}] = history(device)
    end

    test "a raise without a description is stored without one", %{device: device, state: state} do
      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "HighTemp"}, state)

      assert Store.current_alarms_for_device(device) == [{"HighTemp", nil}]
    end

    test "a clear removes the alarm, and is recorded as history", %{device: device, state: state} do
      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "HighTemp"}, state)
      {^state, []} = Alarms.handle_in("cleared", %{"alarm" => "HighTemp"}, state)

      assert Store.current_alarms_for_device(device) == nil
      assert [%{event: "raised"}, %{event: "resolved"}] = history(device)
    end

    test "a repeated event opens no new episode", %{device: device, state: state} do
      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "HighTemp", "description" => "too hot"}, state)
      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "HighTemp", "description" => "hotter"}, state)
      {^state, []} = Alarms.handle_in("cleared", %{"alarm" => "HighTemp"}, state)
      {^state, []} = Alarms.handle_in("cleared", %{"alarm" => "HighTemp"}, state)

      assert [%{event: "raised"}, %{event: "resolved"}] = history(device)
    end

    test "tells an open device page the list moved", %{device: device, state: state} do
      :ok = PubSub.subscribe_reports(device.id)

      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "HighTemp"}, state)

      assert_receive %Broadcast{event: "alarms:updated"}
    end
  end

  describe "snapshots" do
    test "an entry without a usable name is skipped, and its neighbours are not", %{device: device, state: state} do
      {^state, []} =
        Alarms.handle_in(
          "snapshot",
          %{"alarms" => [%{"name" => "Wrong"}, "HighTemp", %{"alarm" => 42}, %{"alarm" => "LowDisk"}]},
          state
        )

      assert Store.current_alarms_for_device(device) == [{"LowDisk", nil}]
    end

    test "reconcile the stored set with the device's", %{device: device, state: state} do
      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "Stale"}, state)

      {^state, []} =
        Alarms.handle_in("snapshot", %{"alarms" => [%{"alarm" => "HighTemp", "description" => "too hot"}]}, state)

      assert Store.current_alarms_for_device(device) == [{"HighTemp", "too hot"}]
    end

    test "an empty snapshot clears everything", %{device: device, state: state} do
      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "HighTemp"}, state)

      {^state, []} = Alarms.handle_in("snapshot", %{"alarms" => []}, state)

      assert Store.current_alarms_for_device(device) == nil
    end
  end

  describe "timestamps" do
    test "a raise is dated by the device's clock", %{device: device, state: state} do
      raised_at = ago(hour: 3)

      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "HighTemp", "raised_at" => iso(raised_at)}, state)

      assert [%{raised_at: ^raised_at}] = stored(device)
      assert [%{timestamp: ^raised_at}] = history(device)
    end

    test "a clear is dated by the device's clock", %{device: device, state: state} do
      cleared_at = ago(minute: 5)

      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "HighTemp", "raised_at" => iso(ago(hour: 1))}, state)
      {^state, []} = Alarms.handle_in("cleared", %{"alarm" => "HighTemp", "cleared_at" => iso(cleared_at)}, state)

      assert [%{event: "raised"}, %{event: "resolved", timestamp: ^cleared_at}] = history(device)
    end

    test "a snapshot carries when each alarm was raised", %{device: device, state: state} do
      # Raised during boot, before the device had connected.
      raised_at = ago(minute: 20)

      {^state, []} =
        Alarms.handle_in(
          "snapshot",
          %{"alarms" => [%{"alarm" => "HighTemp", "raised_at" => iso(raised_at)}, %{"alarm" => "LowDisk"}]},
          state
        )

      assert [%{alarm: "HighTemp", raised_at: ^raised_at}, %{alarm: "LowDisk", raised_at: arrival}] = stored(device)
      assert DateTime.diff(DateTime.utc_now(), arrival) < 60
    end

    test "a time that is not believable is replaced by arrival, and the event still applies", %{
      device: device,
      state: state
    } do
      unbelievable = [
        "1970-01-01T00:00:00Z",
        iso(ago(hour: Alarms.max_age_hours() + 1)),
        iso(DateTime.add(DateTime.utc_now(), Alarms.max_future_skew_minutes() + 5, :minute)),
        "not a timestamp"
      ]

      for {timestamp, i} <- Enum.with_index(unbelievable) do
        {^state, []} = Alarms.handle_in("raised", %{"alarm" => "Alarm#{i}", "raised_at" => timestamp}, state)
      end

      alarms = stored(device)
      assert length(alarms) == length(unbelievable)
      assert Enum.all?(alarms, &(DateTime.diff(DateTime.utc_now(), &1.raised_at) < 60))
    end

    test "a time merely old or slightly ahead is kept", %{device: device, state: state} do
      old = ago(hour: Alarms.max_age_hours() - 1)
      ahead = DateTime.add(DateTime.utc_now(), Alarms.max_future_skew_minutes() - 5, :minute)

      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "Old", "raised_at" => iso(old)}, state)
      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "Ahead", "raised_at" => iso(ahead)}, state)

      assert [%{alarm: "Ahead", raised_at: ^ahead}, %{alarm: "Old", raised_at: ^old}] = stored(device)
    end
  end

  describe "malformed messages" do
    test "are logged rather than crashing, and cost nothing", %{device: device, state: state} do
      assert {^state, []} = Alarms.handle_in("raised", %{"name" => "HighTemp"}, state)
      assert {^state, []} = Alarms.handle_in("cleared", %{}, state)
      # The shape health uses, which a client could easily carry over.
      assert {^state, []} = Alarms.handle_in("snapshot", %{"alarms" => %{"HighTemp" => "too hot"}}, state)
      assert {^state, []} = Alarms.handle_in("report", %{"value" => %{"alarms" => %{}}}, state)

      assert Store.current_alarms_for_device(device) == nil
      assert Alarms.allow?(state.device_info)
    end
  end

  describe "rate limiting" do
    test "a denied event schedules one resync, however many are denied", %{device: device, state: state} do
      state = exhaust(state)

      {state, effects} = Alarms.handle_in("cleared", %{"alarm" => "HighTemp"}, state)

      resync_ms = Alarms.resync_delay_ms()
      assert effects == [{:start_timer, :resync, resync_ms}]
      assert State.get(state, :resync_pending)

      {^state, []} = Alarms.handle_in("raised", %{"alarm" => "LowDisk"}, state)
      {^state, []} = Alarms.handle_in("snapshot", %{"alarms" => []}, state)

      # Denied means not written.
      assert Store.current_alarms_for_device(device) == nil
    end

    test "the resync asks for the whole set, once", %{state: state} do
      state = exhaust(state)
      {state, _effects} = Alarms.handle_in("cleared", %{"alarm" => "HighTemp"}, state)

      {state, effects} = Alarms.handle_info(:resync, state)

      assert {:cancel_timer, :resync} in effects
      assert {:push, "alarms:sync", %{}} in effects
      refute State.get(state, :resync_pending)
    end

    test "a snapshot the device sends unasked makes a pending resync redundant", %{state: state} do
      state = State.assign(state, :resync_pending, true)

      {state, effects} = Alarms.handle_in("snapshot", %{"alarms" => []}, state)

      assert effects == [{:cancel_timer, :resync}]
      refute State.get(state, :resync_pending)
    end

    test "one device's budget is its own", %{state: state} do
      other = %{state.device_info | device_id: state.device_info.device_id + 999_999_999}

      _state = exhaust(state)

      refute Alarms.allow?(state.device_info)
      assert Alarms.allow?(other)
    end
  end

  defp ago(unit_amount) do
    [{unit, amount}] = unit_amount
    DateTime.add(DateTime.utc_now(), -amount, unit)
  end

  defp iso(timestamp), do: DateTime.to_iso8601(timestamp)

  defp stored(device) do
    DeviceAlarm
    |> where(device_id: ^device.id)
    |> order_by(asc: :alarm)
    |> Repo.all()
  end

  defp exhaust(state) do
    Enum.each(1..20, fn _ -> Alarms.allow?(state.device_info) end)
    state
  end

  defp history(device) do
    :ok = Buffer.flush(DeviceAlarmHistory)

    DeviceAlarmHistory
    |> where(device_id: ^device.id)
    |> order_by(asc: :timestamp)
    |> AnalyticsRepo.all()
  end
end
