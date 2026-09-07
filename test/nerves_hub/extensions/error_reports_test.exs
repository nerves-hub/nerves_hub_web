defmodule NervesHub.Extensions.ErrorReportsTest do
  @moduledoc """
  What a device may send, and what the platform keeps.

  Not async: these write to `NervesHub.AnalyticsRepo`, and ClickHouse does not
  take concurrent writes.
  """
  use NervesHub.DataCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.ErrorReports.ErrorReport
  alias NervesHub.ErrorReports.GroupBuffer
  alias NervesHub.Extensions
  alias NervesHub.Extensions.ErrorReports, as: Extension
  alias NervesHub.Extensions.State
  alias NervesHub.Extensions.Unsupported
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})

    :ok = Buffer.flush(ErrorReport)
    :ok = GroupBuffer.flush()
    AnalyticsRepo.query("TRUNCATE TABLE device_error_reports", [])

    %{device: device, state: state(device)}
  end

  describe "which extension a device gets" do
    test "0.1.0 is what this platform implements" do
      assert Extensions.module(:error_reports, Version.parse!("0.1.0")) == Extension
    end

    # There is no single-report version, so a device claiming one is a device
    # this platform cannot serve. Saying so is the correct answer.
    test "there is no 0.0.1 to fall back to" do
      assert Extensions.module(:error_reports, Version.parse!("0.0.1")) == Unsupported
      assert Extensions.module(:error_reports, Version.parse!("0.2.0")) == Unsupported
    end

    test "it is advertised to devices when analytics are on" do
      assert %{"error_reports" => ["0.1.0"]} = Extensions.advertisement()
    end
  end

  describe "attach and detach" do
    test "ask the device for nothing", %{state: state} do
      assert {^state, []} = Extension.attach(state)
      assert {^state, []} = Extension.detach(state)
    end
  end

  describe "handle_in/3 report" do
    test "stores every report in a batch", %{device: device, state: state} do
      {_state, []} =
        Extension.handle_in("report", %{"reports" => reports(["one", "two", "three"])}, state)

      assert reasons(device) == ["one", "three", "two"]
    end

    test "a batch costs one message, not one per report", %{device: device, state: state} do
      # The whole point of batching. The limiter allows a burst of 5 messages,
      # so three batches of twenty get through where sixty single reports would
      # have lost all but five.
      for batch <- 1..3 do
        {_state, []} =
          Extension.handle_in(
            "report",
            %{"reports" => reports(Enum.map(1..20, &"batch #{batch} report #{&1}"))},
            state
          )
      end

      assert length(reasons(device)) == 60
    end

    test "a device that sends too often is cut off", %{device: device, state: state} do
      for i <- 1..30 do
        {_state, []} = Extension.handle_in("report", %{"reports" => reports(["report #{i}"])}, state)
      end

      stored = reasons(device)

      assert length(stored) < 30, "the rate limit let everything through"
      assert stored != [], "the rate limit let nothing through"
    end

    test "an empty batch is not charged for", %{device: device, state: state} do
      for _ <- 1..10 do
        {_state, []} = Extension.handle_in("report", %{"reports" => []}, state)
      end

      {_state, []} = Extension.handle_in("report", %{"reports" => reports(["after the empties"])}, state)

      assert reasons(device) == ["after the empties"]
    end

    test "a batch past the cap keeps what fits and records the gap", %{device: device, state: state} do
      over = Extension.max_reports_per_message() + 7

      {_state, []} =
        Extension.handle_in("report", %{"reports" => reports(Enum.map(1..over, &"report #{&1}"))}, state)

      stored = reasons(device)

      assert length(stored) == Extension.max_reports_per_message() + 1
      assert "report 1" in stored

      assert Enum.any?(stored, &String.contains?(&1, "NervesHub dropped 7 error reports")),
             "nothing recorded the 7 reports that were dropped"
    end

    # A client that declared a version it does not speak. Worth a line in the
    # platform's log, not worth taking the connection's dispatch through Sentry.
    test "a payload that is not a batch is not a crash", %{device: device, state: state} do
      assert {_state, []} = Extension.handle_in("report", %{"kind" => "error"}, state)
      assert reasons(device) == []
    end

    test "reports that are not a list are not a crash", %{device: device, state: state} do
      assert {_state, []} = Extension.handle_in("report", %{"reports" => "nope"}, state)
      assert reasons(device) == []
    end

    test "one unusable report does not take its neighbours with it", %{device: device, state: state} do
      batch = reports(["kept"]) ++ [%{"kind" => "error", "reason" => "no timestamp"}] ++ reports(["also kept"])

      {_state, []} = Extension.handle_in("report", %{"reports" => batch}, state)

      assert reasons(device) == ["also kept", "kept"]
    end
  end

  describe "handle_info/2" do
    test "ignores anything sent to it", %{state: state} do
      assert {^state, []} = Extension.handle_info(:anything, state)
    end
  end

  describe "enabled?/0" do
    test "follows the analytics flag, since occurrences need ClickHouse" do
      original = Application.get_env(:nerves_hub, :analytics_enabled)
      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)

      Application.put_env(:nerves_hub, :analytics_enabled, false)
      refute Extension.enabled?()

      Application.put_env(:nerves_hub, :analytics_enabled, true)
      assert Extension.enabled?()
    end
  end

  defp state(device) do
    State.new(%DeviceInfo{
      device_id: device.id,
      org_id: device.org_id,
      product_id: device.product_id,
      device_identifier: device.identifier,
      firmware_metadata: %{uuid: "fw-1"}
    })
  end

  defp reports(reasons), do: Enum.map(reasons, &report/1)

  defp report(reason) do
    %{
      "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
      "kind" => "error",
      "reason" => reason
    }
  end

  defp reasons(device) do
    import Ecto.Query

    :ok = Buffer.flush(ErrorReport)
    :ok = GroupBuffer.flush()

    ErrorReport
    |> where([r], r.device_id == ^device.id)
    |> select([r], r.reason)
    |> AnalyticsRepo.all()
    |> Enum.sort()
  end
end
