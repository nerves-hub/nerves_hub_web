defmodule NervesHub.Devices.LogLinesTest do
  # These tests are not async because they interact with the AnalyticsRepo,
  # which is a ClickHouse database that does not support concurrent writes.
  use NervesHub.DataCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.LogLine
  alias NervesHub.Devices.LogLines
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})
    device2 = Fixtures.device_fixture(org, product, firmware)
    device3 = Fixtures.device_fixture(org, product, firmware)

    :ok = Buffer.flush(LogLine)
    AnalyticsRepo.query("TRUNCATE TABLE device_log_lines", [])

    {:ok,
     %{
       device: device,
       device2: device2,
       device3: device3
     }}
  end

  test "create!/2", %{device: device} do
    level = "info"
    message = "something happened"
    logged_at = DateTime.utc_now()
    device_id = device.id
    product_id = device.product_id

    {:ok, log} =
      to_device_info(device)
      |> LogLines.async_create(%{
        "timestamp" => logged_at,
        "level" => level,
        "message" => message
      })

    %LogLine{
      timestamp: ^logged_at,
      device_id: ^device_id,
      product_id: ^product_id,
      level: ^level,
      message: ^message
    } = log

    :ok = Buffer.flush(LogLine)

    [
      %LogLine{
        timestamp: ^logged_at,
        device_id: ^device_id,
        product_id: ^product_id,
        level: ^level,
        message: ^message
      }
    ] = AnalyticsRepo.all(LogLine)
  end

  test "create!/2 - unix timestamp is extracted from the meta information (string format)", %{
    device: device
  } do
    level = "info"
    message = "something happened"
    logged_at = DateTime.utc_now()
    device_id = device.id
    product_id = device.product_id

    {:ok, log} =
      to_device_info(device)
      |> LogLines.async_create(%{
        "level" => level,
        "message" => message,
        "meta" => %{"time" => logged_at |> DateTime.to_unix(:microsecond) |> to_string()}
      })

    %LogLine{
      timestamp: ^logged_at,
      device_id: ^device_id,
      product_id: ^product_id,
      level: ^level,
      message: ^message
    } = log

    :ok = Buffer.flush(LogLine)

    [
      %LogLine{
        timestamp: ^logged_at,
        device_id: ^device_id,
        product_id: ^product_id,
        level: ^level,
        message: ^message
      }
    ] = AnalyticsRepo.all(LogLine)
  end

  test "recent/1", %{device: device, device2: device2} do
    for _ <- 0..30 do
      random_log(device)
      random_log(device2)
    end

    :ok = Buffer.flush(LogLine)

    recent = LogLines.recent(device)

    assert length(recent) == 25
    assert Enum.all?(recent, &(&1.device_id == device.id))
  end

  describe "for_device/2" do
    test "filters by level", %{device: device} do
      log(device, level: "info", message: "info line")
      log(device, level: "error", message: "error line")
      log(device, level: "debug", message: "debug line")

      :ok = Buffer.flush(LogLine)

      assert messages(LogLines.for_device(device, levels: ["error"])) == ["error line"]

      assert messages(LogLines.for_device(device, levels: ["error", "debug"], order: :asc)) == [
               "error line",
               "debug line"
             ]

      assert LogLines.for_device(device, levels: ["emergency"]) == []
    end

    test "bounds a window with since and before", %{device: device} do
      now = DateTime.utc_now()

      log(device, message: "old", timestamp: DateTime.add(now, -3600))
      log(device, message: "recent", timestamp: DateTime.add(now, -60))

      :ok = Buffer.flush(LogLine)

      # since is inclusive, before is exclusive, so the timestamp of the oldest
      # line in a page is the next page's before without repeating that line.
      assert messages(LogLines.for_device(device, since: DateTime.add(now, -60))) == ["recent"]
      assert messages(LogLines.for_device(device, before: DateTime.add(now, -60))) == ["old"]
      assert LogLines.for_device(device, since: DateTime.add(now, -30)) == []
    end

    test "orders and limits", %{device: device} do
      now = DateTime.utc_now()

      for n <- 1..3, do: log(device, message: "line #{n}", timestamp: DateTime.add(now, -n))

      :ok = Buffer.flush(LogLine)

      assert messages(LogLines.for_device(device)) == ["line 1", "line 2", "line 3"]
      assert messages(LogLines.for_device(device, order: :asc)) == ["line 3", "line 2", "line 1"]
      assert messages(LogLines.for_device(device, limit: 1)) == ["line 1"]
    end

    test "only returns the device's own lines", %{device: device, device2: device2} do
      log(device, message: "mine")
      log(device2, message: "theirs")

      :ok = Buffer.flush(LogLine)

      assert messages(LogLines.for_device(device)) == ["mine"]
    end
  end

  defp messages(log_lines), do: Enum.map(log_lines, & &1.message)

  defp log(device, attrs) do
    {:ok, log_line} =
      LogLines.async_create(to_device_info(device), %{
        "timestamp" => attrs[:timestamp] || DateTime.utc_now(),
        "level" => attrs[:level] || "info",
        "message" => attrs[:message] || "hello"
      })

    log_line
  end

  defp random_word(n \\ 6) do
    1..n |> Enum.map(fn _ -> Enum.random(?a..?z) end) |> to_string()
  end

  defp random_log(device) do
    attrs = %{
      "timestamp" => DateTime.utc_now(),
      "level" => Enum.random(["error", "warning", "info", "debug"]),
      "message" => random_word()
    }

    {:ok, log_line} = LogLines.async_create(to_device_info(device), attrs)

    log_line
  end

  def to_device_info(device) do
    %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }
  end
end
