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
    now = DateTime.utc_now()

    rows =
      for i <- 0..30, dev <- [device, device2] do
        LogLine.create_changeset(dev.id, dev.product_id, %{
          "timestamp" => DateTime.add(now, i, :millisecond),
          "level" => "info",
          "message" => random_word()
        }).changes
      end

    AnalyticsRepo.insert_all(LogLine, rows, settings: [async_insert: 1])

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

    test "searches the message, ignoring case", %{device: device} do
      log(device, message: "Failed to reach the sensor bus")
      log(device, message: "SENSOR BUS back online")
      log(device, message: "polling temperature")

      :ok = Buffer.flush(LogLine)

      assert length(LogLines.for_device(device, search: "sensor bus")) == 2
      assert messages(LogLines.for_device(device, search: "temperature")) == ["polling temperature"]
      assert LogLines.for_device(device, search: "nothing logged this") == []
    end

    test "searches for wildcards literally", %{device: device} do
      log(device, message: "battery at 100% charge")
      log(device, message: "polling temperature")

      :ok = Buffer.flush(LogLine)

      # As a LIKE pattern a bare % matches every line. As a substring it only
      # finds the line that has one.
      assert messages(LogLines.for_device(device, search: "%")) == ["battery at 100% charge"]
      assert messages(LogLines.for_device(device, search: "100%")) == ["battery at 100% charge"]
    end

    test "combines search with the other filters", %{device: device} do
      log(device, level: "error", message: "sensor bus gone")
      log(device, level: "info", message: "sensor bus fine")

      :ok = Buffer.flush(LogLine)

      assert messages(LogLines.for_device(device, search: "sensor bus", levels: ["error"])) == ["sensor bus gone"]
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

  describe "LogLine.create_changeset/3" do
    test "missing timestamp produces invalid changeset", %{device: device} do
      changeset = LogLine.create_changeset(device.id, device.product_id, %{"message" => "hi", "level" => "info"})
      refute changeset.valid?
      assert changeset.errors[:timestamp] != nil
    end

    test "valid params produce a valid changeset", %{device: device} do
      changeset =
        LogLine.create_changeset(device.id, device.product_id, %{
          "timestamp" => DateTime.utc_now(),
          "level" => "info",
          "message" => "hello"
        })

      assert changeset.valid?
    end

    test "maybe_set_timestamp - unix microsecond string in meta.time sets the timestamp", %{
      device: device
    } do
      logged_at = DateTime.utc_now()
      unix_us = logged_at |> DateTime.to_unix(:microsecond) |> to_string()

      changeset =
        LogLine.create_changeset(device.id, device.product_id, %{
          "level" => "info",
          "message" => "hello",
          "meta" => %{"time" => unix_us}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :timestamp) == logged_at
    end

    test "maybe_set_timestamp - explicit timestamp is used as-is", %{device: device} do
      logged_at = DateTime.utc_now()

      changeset =
        LogLine.create_changeset(device.id, device.product_id, %{
          "timestamp" => logged_at,
          "level" => "info",
          "message" => "hello"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :timestamp) == logged_at
    end

    test "maybe_set_timestamp - missing timestamp and no meta.time makes changeset invalid", %{
      device: device
    } do
      changeset =
        LogLine.create_changeset(device.id, device.product_id, %{
          "level" => "info",
          "message" => "hello"
        })

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :timestamp)
    end

    test "format_message - charlist message is converted to string", %{device: device} do
      changeset =
        LogLine.create_changeset(device.id, device.product_id, %{
          "timestamp" => DateTime.utc_now(),
          "level" => "info",
          "message" => ~c"hello charlist"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :message) == "hello charlist"
    end

    test "format_message - non-string non-charlist is inspected", %{device: device} do
      changeset =
        LogLine.create_changeset(device.id, device.product_id, %{
          "timestamp" => DateTime.utc_now(),
          "level" => "info",
          "message" => 42
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :message) == "42"
    end
  end

  defp random_word(n \\ 6) do
    1..n |> Enum.map(fn _ -> Enum.random(?a..?z) end) |> to_string()
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
