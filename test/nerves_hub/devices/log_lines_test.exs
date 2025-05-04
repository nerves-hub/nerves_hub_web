defmodule NervesHub.Devices.LogLinesTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Devices.LogLine
  alias NervesHub.Devices.LogLines
  alias NervesHub.Fixtures
  # alias NervesHub.Repo

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})
    device2 = Fixtures.device_fixture(org, product, firmware)
    device3 = Fixtures.device_fixture(org, product, firmware)

    {:ok,
     %{
       device: device,
       device2: device2,
       device3: device3
     }}
  end

  test "create!/2", %{device: device} do
    level = :info
    message = "something happened"
    logged_at = now()
    device_id = device.id

    log = LogLines.create!(device, %{level: level, logged_at: logged_at, message: message})

    %LogLine{
      id: log_id,
      device_id: ^device_id,
      logged_at: ^logged_at,
      level: ^level,
      message: ^message
    } = log

    [
      %LogLine{
        id: ^log_id,
        device_id: ^device_id,
        logged_at: ^logged_at,
        level: ^level,
        message: ^message
      }
    ] = Repo.preload(device, :device_logs).device_logs
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

  test "associations", %{device: device1, device2: device2} do
    log11 = random_log(device1)
    log12 = random_log(device1)
    log21 = random_log(device2)
    log22 = random_log(device2)

    [device1, device2] = Repo.preload([device1, device2], :device_logs)

    2 = length(device1.device_logs)
    2 = length(device2.device_logs)

    assert Enum.sort([log11.id, log12.id]) == Enum.sort(device1.device_logs |> Enum.map(& &1.id))
    assert Enum.sort([log21.id, log22.id]) == Enum.sort(device2.device_logs |> Enum.map(& &1.id))
  end

  defp now() do
    NaiveDateTime.utc_now()
  end

  defp random_word(n \\ 6) do
    1..n |> Enum.map(fn _ -> Enum.random(?a..?z) end) |> to_string()
  end

  defp random_log(device) do
    attrs = %{
      level: Enum.random(["error", "warning", "info", "debug"]),
      logged_at: now(),
      message: random_word()
    }

    LogLines.create!(device, attrs)
  end
end
