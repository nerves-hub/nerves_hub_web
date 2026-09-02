defmodule NervesHub.Devices.DeviceMessagesTest do
  # These tests are not async because they interact with the AnalyticsRepo,
  # which is a ClickHouse database that does not support concurrent writes.
  use NervesHub.DataCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.DeviceMessage
  alias NervesHub.Devices.DeviceMessages
  alias NervesHub.Devices.DeviceMessages.Payload
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})

    :ok = Buffer.flush(DeviceMessage)
    AnalyticsRepo.query("TRUNCATE TABLE device_messages", [])

    {:ok, %{device: device, other_device: Fixtures.device_fixture(org, product, firmware)}}
  end

  describe "record/5" do
    test "stores a message received from a device", %{device: device} do
      :ok =
        DeviceMessages.record(device_info(device), :received, :device, "fwup_progress", %{
          "value" => 42
        })

      assert [message] = read_back(device)

      assert message.direction == "received"
      assert message.topic == "device"
      assert message.event == "fwup_progress"
      assert message.payload == ~s({"value":42})
      assert message.device_id == device.id
      assert message.product_id == device.product_id
      assert message.org_id == device.org_id
      refute DeviceMessage.truncated?(message)
    end

    test "stores a message sent to a device", %{device: device} do
      :ok = DeviceMessages.record(device, :sent, :device, "reboot", %{})

      assert [message] = read_back(device)
      assert message.direction == "sent"
      assert message.event == "reboot"
      assert message.payload == "{}"
    end

    test "only returns messages for the requested device", %{
      device: device,
      other_device: other_device
    } do
      :ok = DeviceMessages.record(device, :sent, :device, "reboot", %{})
      :ok = DeviceMessages.record(other_device, :sent, :device, "identify", %{})

      assert [%{event: "reboot"}] = read_back(device)
      assert [%{event: "identify"}] = read_back(other_device)
    end

    test "records nothing when analytics is disabled", %{device: device} do
      Application.put_env(:nerves_hub, :analytics_enabled, false)
      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, true) end)

      :ok = DeviceMessages.record(device, :sent, :device, "reboot", %{})

      assert [] == read_back(device)
    end
  end

  describe "record_size_only/5" do
    test "records the size of console data but not its contents", %{device: device} do
      :ok =
        DeviceMessages.record_size_only(device, :received, :console, "up", %{
          "data" => "export SECRET=hunter2\n"
        })

      assert [message] = read_back(device)

      assert message.topic == "console"
      assert message.payload == ""
      assert message.payload_bytes == byte_size("export SECRET=hunter2\n")
      assert DeviceMessage.metadata_only?(message)
    end
  end

  describe "recent/2" do
    test "filters by direction and topic", %{device: device} do
      :ok = DeviceMessages.record(device, :received, :device, "status_update", %{})
      :ok = DeviceMessages.record(device, :sent, :device, "reboot", %{})
      :ok = DeviceMessages.record(device, :sent, :extensions, "health:check", %{})
      :ok = Buffer.flush(DeviceMessage)

      assert [%{event: "status_update"}] = DeviceMessages.recent(device, direction: "received")

      assert ["health:check", "reboot"] ==
               device |> DeviceMessages.recent(direction: "sent") |> Enum.map(& &1.event) |> Enum.sort()

      assert [%{event: "health:check"}] = DeviceMessages.recent(device, topic: "extensions")
    end

    test "honours the limit", %{device: device} do
      for n <- 1..5, do: DeviceMessages.record(device, :sent, :device, "reboot", %{"n" => n})
      :ok = Buffer.flush(DeviceMessage)

      assert 2 == device |> DeviceMessages.recent(limit: 2) |> length()
    end
  end

  describe "payload redaction" do
    test "strips the query string from a firmware url, keeping the object", %{device: device} do
      url = "https://firmware.example.com/org/1/fw.fw?X-Amz-Signature=deadbeef&X-Amz-Expires=300"

      :ok = DeviceMessages.record(device, :sent, :device, "update", %{"url" => url})

      assert [message] = read_back(device)

      assert message.payload =~ "https://firmware.example.com/org/1/fw.fw"
      refute message.payload =~ "deadbeef"
      assert message.payload =~ "[redacted]"
    end

    test "redacts sensitive values nested inside a payload", %{device: device} do
      :ok =
        DeviceMessages.record(device, :sent, :device, "update", %{
          "firmware_meta" => %{"uuid" => "abc-123", "token" => "s3cret"},
          "url" => "https://example.com/fw.fw"
        })

      assert [message] = read_back(device)

      assert message.payload =~ "abc-123"
      refute message.payload =~ "s3cret"
    end

    # The `update` message carries an `%UpdatePayload{}`, not a plain map, and
    # its `firmware_url` is presigned — a bearer token for the firmware and the
    # single most sensitive thing the platform sends a device. A struct is also
    # a map, so redaction that only walked plain maps would skip it silently.
    test "redacts the firmware url on a real update payload struct", %{device: device} do
      payload = %UpdatePayload{
        update_available: true,
        firmware_url: "https://firmware.example.com/org/1/fw.fw?X-Amz-Signature=deadbeef",
        firmware_meta: %{uuid: "abc-123"},
        size: 1024,
        checksum: "cafe",
        deployment_id: 7,
        deployment_group: %{name: "should not be stored"}
      }

      :ok = DeviceMessages.record(device, :sent, :device, "update", payload)

      assert [message] = read_back(device)

      assert message.payload =~ "https://firmware.example.com/org/1/fw.fw"
      refute message.payload =~ "deadbeef"

      # Encoding through the struct's own encoder keeps the stored row to what
      # the device actually receives.
      assert message.payload =~ "abc-123"
      refute message.payload =~ "should not be stored"
    end

    test "redacts a url that cannot be parsed rather than guessing" do
      assert %{"url" => "[redacted]"} = Payload.redact(%{"url" => "not a url at all"})
    end

    test "leaves ordinary values alone" do
      payload = %{"value" => 42, "list" => [1, 2, 3], "nested" => %{"ok" => true}}

      assert payload == Payload.redact(payload)
    end
  end

  describe "payload truncation" do
    test "caps an oversized payload and records the original size", %{device: device} do
      big = String.duplicate("a", 20_000)

      :ok = DeviceMessages.record(device, :received, :device, "noisy", %{"blob" => big})

      assert [message] = read_back(device)

      assert DeviceMessage.truncated?(message)
      assert byte_size(message.payload) == 8_192
      assert message.payload_bytes > 20_000
    end
  end

  describe "batching" do
    # `NervesHub.Analytics.Buffer` has its own tests for how it batches; what
    # matters here is that a `DeviceMessage` survives the trip through it. The
    # buffer flattens a changeset through the struct and writes the batch as one
    # `insert_all`, so every row has to carry every column — a field left off
    # the changeset would fail the whole batch, not just its own row.
    test "a batch of messages arrives complete", %{device: device} do
      for n <- 1..250 do
        DeviceMessages.record(device, :received, :device, "tick", %{"n" => n})
      end

      :ok = Buffer.flush(DeviceMessage)

      messages = DeviceMessages.recent(device, limit: 500)

      assert 250 == length(messages)

      assert Enum.all?(messages, fn message ->
               message.device_id == device.id and message.topic == "device" and
                 message.event == "tick" and message.payload =~ ~s("n":)
             end)
    end
  end

  defp read_back(device) do
    :ok = Buffer.flush(DeviceMessage)
    DeviceMessages.recent(device)
  end

  defp device_info(device) do
    %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }
  end
end
