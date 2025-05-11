defmodule NervesHub.Devices.LogLinesTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Devices.LogLine
  alias NervesHub.Devices.LogLines

  alias NervesHub.Fixtures

  alias NervesHub.AnalyticsRepo

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})
    device2 = Fixtures.device_fixture(org, product, firmware)
    device3 = Fixtures.device_fixture(org, product, firmware)

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

    log =
      LogLines.create!(device, %{"timestamp" => logged_at, "level" => level, "message" => message})

    %LogLine{
      timestamp: ^logged_at,
      device_id: ^device_id,
      product_id: ^product_id,
      level: ^level,
      message: ^message
    } = log

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

    recent = LogLines.recent(device)

    assert length(recent) == 25
    assert Enum.all?(recent, &(&1.device_id == device.id))
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

    LogLines.create!(device, attrs)
  end
end
