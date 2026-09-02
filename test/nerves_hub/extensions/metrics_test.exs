defmodule NervesHub.Extensions.MetricsTest do
  @moduledoc """
  The metrics extension: the pace it sets, and what it will accept from a
  device.

  Storage is `NervesHub.DeviceMetricsTest`'s subject; this is about the
  protocol around it -- batching, rate limiting, and the device-supplied
  timestamps that make batching worth having.
  """

  use NervesHub.DataCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Extensions.Metrics
  alias NervesHub.Extensions.PubSub
  alias NervesHub.Extensions.State
  alias NervesHub.Fixtures
  alias Phoenix.Socket.Broadcast

  @watched_ms to_timeout(minute: 1)
  @idle_ms to_timeout(minute: 15)

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

    AnalyticsRepo.query!("TRUNCATE TABLE device_metrics")
    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_metrics") end)

    %{device: device, device_info: device_info, state: State.new(device_info)}
  end

  describe "attaching" do
    test "asks straight away and settles into the platform interval", %{device: device, state: state} do
      {state, effects} = Metrics.attach(state)

      assert State.get(state, :mode) == :idle
      assert {:group_join, "device:metrics/#{device.id}"} in effects
      assert {:tick, :check} in effects
      assert {:start_timer, :check, first_ms, @idle_ms} = timer(effects)

      # Offset so a fleet attaching together does not answer together.
      assert first_ms in 1..@idle_ms
    end

    test "picks up a page that was already open", %{device: device, state: state} do
      :ok = PubSub.watch(device.id, :metrics)

      {state, effects} = Metrics.attach(state)

      assert State.get(state, :mode) == :watched
      assert {:start_timer, :check, @watched_ms} = timer(effects)
    end

    test "detaching gives up the timer and the group", %{device: device, state: state} do
      {state, _effects} = Metrics.attach(state)

      {state, effects} = Metrics.detach(state)

      assert State.get(state, :mode) == nil
      assert {:cancel_timer, :check} in effects
      assert {:group_leave, "device:metrics/#{device.id}"} in effects
    end

    test "a page open on health does not speed metrics up", %{device: device, state: state} do
      :ok = PubSub.watch(device.id, :health)

      {state, _effects} = Metrics.attach(state)

      assert State.get(state, :mode) == :idle
    end
  end

  describe "checking" do
    test "asks the device", %{device: device, state: state} do
      :ok = PubSub.watch(device.id, :metrics)
      {state, _effects} = Metrics.attach(state)

      assert {_state, [{:push, "metrics:check", %{}}]} = Metrics.handle_info(:check, state)
    end

    test "uses a custom interval from application config", %{state: state} do
      original = Application.get_env(:nerves_hub, :extension_config)
      Application.put_env(:nerves_hub, :extension_config, metrics: [interval_minutes: 5])
      on_exit(fn -> Application.put_env(:nerves_hub, :extension_config, original) end)

      {_state, effects} = Metrics.attach(state)

      expected = to_timeout(minute: 5)
      assert Enum.any?(effects, &match?({:start_timer, :check, _, ^expected}, &1))
    end
  end

  describe "reporting" do
    test "stores every report in the batch, each at its own timestamp", %{device: device, state: state} do
      earlier = at(-120)
      later = at(-60)

      {^state, []} =
        Metrics.handle_in(
          "report",
          %{
            "reports" => [
              %{"timestamp" => iso(earlier), "metrics" => %{"cpu_temp" => 40.0}},
              %{"timestamp" => iso(later), "metrics" => %{"cpu_temp" => 41.0}}
            ]
          },
          state
        )

      assert [%{value: 40.0}, %{value: 41.0}] = rows(device)
    end

    test "an empty batch stores nothing and costs nothing", %{device: device, state: state} do
      assert {^state, []} = Metrics.handle_in("report", %{"reports" => []}, state)
      assert rows(device) == []

      # The budget was not spent, so a real report in the same second still lands.
      assert Metrics.allow?(state.device_info)
    end

    test "tells whoever is watching the device's page about fresh numbers", %{device: device, state: state} do
      :ok = PubSub.subscribe_reports(device.id)

      {^state, []} =
        Metrics.handle_in(
          "report",
          %{"reports" => [%{"timestamp" => iso(at(-60)), "metrics" => %{"cpu_temp" => 40.0}}]},
          state
        )

      assert_receive %Broadcast{event: "metrics_report"}

      # An empty batch stored nothing, so there is nothing to announce.
      {^state, []} = Metrics.handle_in("report", %{"reports" => []}, state)
      refute_receive %Broadcast{event: "metrics_report"}, 100
    end

    test "a report with an unreadable timestamp is skipped, and its neighbours are not", %{
      device: device,
      state: state
    } do
      {^state, []} =
        Metrics.handle_in(
          "report",
          %{
            "reports" => [
              %{"metrics" => %{"cpu_temp" => 1.0}},
              %{"timestamp" => "not a timestamp", "metrics" => %{"cpu_temp" => 2.0}},
              %{"timestamp" => iso(at(-60)), "metrics" => %{"cpu_temp" => 3.0}}
            ]
          },
          state
        )

      assert [%{value: 3.0}] = rows(device)
    end

    test "a report whose clock is wildly wrong is skipped", %{device: device, state: state} do
      skewed = DateTime.add(DateTime.utc_now(), -(Metrics.max_clock_skew_hours() + 1), :hour)

      {^state, []} =
        Metrics.handle_in(
          "report",
          %{"reports" => [%{"timestamp" => iso(skewed), "metrics" => %{"cpu_temp" => 1.0}}]},
          state
        )

      assert rows(device) == []
    end

    test "a report merely late is kept", %{device: device, state: state} do
      late = DateTime.add(DateTime.utc_now(), -(Metrics.max_clock_skew_hours() - 1), :hour)

      {^state, []} =
        Metrics.handle_in(
          "report",
          %{"reports" => [%{"timestamp" => iso(late), "metrics" => %{"cpu_temp" => 1.0}}]},
          state
        )

      assert [%{value: 1.0}] = rows(device)
    end

    test "a batch longer than the cap is trimmed to it", %{device: device, state: state} do
      max = Metrics.max_reports_per_message()

      reports =
        for i <- 1..(max + 5) do
          %{"timestamp" => iso(at(-i)), "metrics" => %{"cpu_temp" => i * 1.0}}
        end

      {^state, []} = Metrics.handle_in("report", %{"reports" => reports}, state)

      assert length(rows(device)) == max
    end

    test "a payload that is not a batch is logged rather than crashing", %{device: device, state: state} do
      # A client that declared 0.1.0 and sent the shape health uses.
      assert {^state, []} = Metrics.handle_in("report", %{"value" => %{"metrics" => %{"cpu_temp" => 1.0}}}, state)

      assert rows(device) == []
    end
  end

  describe "rate limiting" do
    test "one message costs one token, whatever it carries", %{state: state} do
      report = %{"timestamp" => iso(at(-1)), "metrics" => %{"cpu_temp" => 1.0}}

      # The bucket's capacity, spent on single-report messages.
      for _ <- 1..5, do: assert(Metrics.allow?(state.device_info))

      refute Metrics.allow?(state.device_info)

      # A message carrying sixty readings would have cost exactly the same.
      assert is_map(report)
    end

    test "one device's budget is its own", %{state: state, device: device} do
      other = %{device_info(state) | device_id: device.id + 1}

      for _ <- 1..6, do: Metrics.allow?(state.device_info)

      refute Metrics.allow?(state.device_info)
      assert Metrics.allow?(other)
    end
  end

  defp device_info(state), do: state.device_info

  defp timer(effects) do
    Enum.find(effects, &match?({:start_timer, :check, _}, &1)) ||
      Enum.find(effects, &match?({:start_timer, :check, _, _}, &1))
  end

  defp at(seconds_ago), do: DateTime.add(DateTime.utc_now(), seconds_ago, :second)

  defp iso(timestamp), do: DateTime.to_iso8601(timestamp)

  defp rows(device) do
    :ok = Buffer.flush(DeviceMetric)

    DeviceMetric
    |> where(device_id: ^device.id)
    |> order_by(asc: :timestamp)
    |> AnalyticsRepo.all()
  end
end
