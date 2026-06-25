defmodule NervesHub.AdvancedQueryFixtures do
  @moduledoc """
  Shared setup for the advanced query tests (lexer/parser/compiler and the
  `Devices.filter` integration tests).

  Builds one product and a small, carefully-shaped device set that exercises
  every column's edge cases:

    * `tagged`          - tags ["prod", "beta"], healthy + an active alarm
    * `untagged`        - nil tags, firmware updates disabled
    * `connected`       - empty tags, a connected connection reporting wifi,
                          warning health with no alarms, status :provisioned
    * `never_connected` - empty tags, updates blocked (penalty box)

  It deliberately uses its own temp directory rather than the ExUnit `:tmp_dir`,
  so the firmware build never depends on the (sometimes special-character-laden)
  test name.
  """

  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  @doc """
  ExUnit `setup` callback. Returns a map merged into the test context with
  `:product`, `:firmware`, `:platform`, and the four named devices.
  """
  def setup_devices(_context \\ %{}) do
    dir = tmp_dir()
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: dir})

    tagged = Fixtures.device_fixture(org, product, firmware, %{identifier: "tagged", tags: ["prod", "beta"]})

    untagged =
      Fixtures.device_fixture(org, product, firmware, %{identifier: "untagged", tags: nil, updates_enabled: false})

    connected =
      Fixtures.device_fixture(org, product, firmware, %{identifier: "connected", tags: [], status: :provisioned})

    Fixtures.device_connection_fixture(connected, %{status: :connected, metadata: %{"connection_types" => ["wifi"]}})

    never_connected =
      Fixtures.device_fixture(org, product, firmware, %{
        identifier: "never_connected",
        tags: [],
        updates_blocked_until: DateTime.add(DateTime.utc_now(), 1, :day)
      })

    # "tagged" and "connected" get health records; the others have none (= unknown).
    # "tagged" has an active alarm; "connected" has none.
    {:ok, _} = save_health(tagged, :healthy, %{"alarms" => %{"SomeAlarm" => "boom"}})
    {:ok, _} = save_health(connected, :warning, %{"alarms" => %{}})

    %{
      user: user,
      org: org,
      org_key: org_key,
      product: product,
      firmware: firmware,
      platform: tagged.firmware_metadata.platform,
      tagged: tagged,
      untagged: untagged,
      connected: connected,
      never_connected: never_connected
    }
  end

  @doc "Saves a health record (and updates the device's latest health)."
  def save_health(device, status, data \\ %{}) do
    {:ok, _} =
      Devices.save_device_health(%{
        "device_id" => device.id,
        "data" => data,
        "status" => status,
        "status_reasons" => %{}
      })
  end

  @doc "Inserts a metric reading `seconds_ago` in the past (to control which is latest)."
  def save_metric(device, key, value, seconds_ago) do
    inserted_at = DateTime.add(DateTime.utc_now(), -seconds_ago, :second)

    DeviceMetric.save_with_timestamp(%{
      device_id: device.id,
      key: key,
      value: value,
      inserted_at: inserted_at
    })
    |> Repo.insert!()
  end

  defp tmp_dir() do
    dir = Path.join(System.tmp_dir!(), "advanced_query_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end
end
