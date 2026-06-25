defmodule NervesHub.Devices.AdvancedQuery.CompilerTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query
  import NervesHub.AdvancedQueryFixtures, only: [save_metric: 4]

  alias NervesHub.Devices.AdvancedQuery.Compiler
  alias NervesHub.Devices.AdvancedQuery.Parser
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  setup {NervesHub.AdvancedQueryFixtures, :setup_devices}

  defp run(product, query) do
    {:ok, ast} = Parser.parse(query, product.id)

    Device
    |> join(:left, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:left, [d, dc], dh in assoc(d, :latest_health), as: :latest_health)
    |> join(:left, [d], ifu in assoc(d, :inflight_update), as: :inflight_update)
    |> where([d], d.product_id == ^product.id)
    |> Compiler.apply_query(ast)
    |> select([d], d.identifier)
    |> Repo.all()
    |> Enum.sort()
  end

  describe "apply_query/2" do
    test "platform equality", %{product: product, platform: platform} do
      assert run(product, ~s|platform = "#{platform}"|) == ["connected", "never_connected", "tagged", "untagged"]
      assert run(product, ~s|platform != "#{platform}"|) == []
    end

    test "firmware matches the device's firmware uuid", %{product: product, firmware: firmware, untagged: untagged} do
      # Point one device at a different firmware uuid so the match discriminates.
      # The compiler only compares firmware_metadata->>'uuid', so the uuid need
      # not be a registered firmware for this (compiler-level) assertion.
      other_uuid = "00000000-0000-0000-0000-000000000000"

      {:ok, _} =
        untagged
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_embed(
          :firmware_metadata,
          Ecto.Changeset.change(untagged.firmware_metadata, uuid: other_uuid)
        )
        |> Repo.update()

      assert run(product, ~s|firmware = "#{firmware.uuid}"|) == ["connected", "never_connected", "tagged"]
      assert run(product, ~s|firmware != "#{firmware.uuid}"|) == ["untagged"]
    end

    test "deployment_group matches by name and inequality includes ungrouped devices", %{
      product: product,
      firmware: firmware,
      tagged: tagged
    } do
      group =
        Repo.insert!(%DeploymentGroup{
          product_id: product.id,
          org_id: firmware.org_id,
          name: "Test Group #{System.unique_integer([:positive])}"
        })

      {1, _} = Repo.update_all(where(Device, id: ^tagged.id), set: [deployment_id: group.id])

      assert run(product, ~s|deployment_group = "#{group.name}"|) == ["tagged"]
      assert run(product, ~s|deployment_group != "#{group.name}"|) == ["connected", "never_connected", "untagged"]

      # the not-set sentinel matches devices with no deployment group
      assert run(product, ~s|deployment_group = ":not_set"|) == ["connected", "never_connected", "untagged"]
      assert run(product, ~s|deployment_group != ":not_set"|) == ["tagged"]
    end

    test "identifier like/not like uses case-insensitive SQL patterns", %{product: product} do
      # wildcards are supplied by the user
      assert run(product, ~s|identifier like "%nect%"|) == ["connected", "never_connected"]
      assert run(product, ~s|identifier like "CONNECTED"|) == ["connected"]
      assert run(product, ~s|identifier like "never%"|) == ["never_connected"]
      assert run(product, ~s|identifier not like "%nect%"|) == ["tagged", "untagged"]
    end

    test "tags contains", %{product: product} do
      assert run(product, ~s|tags contains "prod"|) == ["tagged"]
    end

    test "tags not_contains includes devices with no tags at all", %{product: product} do
      assert run(product, ~s|tags not_contains "prod"|) == ["connected", "never_connected", "untagged"]
    end

    test "tags :not_set matches devices with no tags (nil or empty)", %{product: product} do
      # "untagged" has nil tags; "connected"/"never_connected" have empty arrays.
      assert run(product, ~s|tags contains ":not_set"|) == ["connected", "never_connected", "untagged"]
      assert run(product, ~s|tags not_contains ":not_set"|) == ["tagged"]
    end

    test "and combines comparisons", %{product: product, platform: platform} do
      assert run(product, ~s|platform = "#{platform}" and tags contains "prod"|) == ["tagged"]
    end

    test "or combines comparisons", %{product: product} do
      assert run(product, ~s|tags contains "prod" or tags contains "beta"|) == ["tagged"]
    end

    test "not negates a comparison, including nil tags", %{product: product} do
      assert run(product, ~s|not tags contains "prod"|) == ["connected", "never_connected", "untagged"]
    end

    test "parenthesized grouping changes precedence", %{product: product} do
      # "tagged" is not connected; "connected" has no tags. AND binds tighter than OR,
      # so the ungrouped form matches "tagged" via its tags, regardless of connection.
      ungrouped = ~s|connection = "connected" and tags contains "beta" or tags contains "prod"|
      assert run(product, ungrouped) == ["tagged"]

      # Grouping the OR means a device must be connected *and* (beta or prod) tagged -
      # no device satisfies both, so nothing matches.
      grouped = ~s|connection = "connected" and (tags contains "beta" or tags contains "prod")|
      assert run(product, grouped) == []
    end

    test "connection equality", %{product: product} do
      assert run(product, ~s|connection = "connected"|) == ["connected"]
      assert run(product, ~s|connection != "connected"|) == ["never_connected", "tagged", "untagged"]
    end

    test "connection not_seen matches devices that have never connected", %{product: product} do
      assert run(product, ~s|connection = "not_seen"|) == ["never_connected", "tagged", "untagged"]
      assert run(product, ~s|connection != "not_seen"|) == ["connected"]
    end

    test "health_status equality", %{product: product} do
      assert run(product, ~s|health_status = "healthy"|) == ["tagged"]
      assert run(product, ~s|health_status = "warning"|) == ["connected"]
    end

    test "health_status unknown matches devices with no health record", %{product: product} do
      assert run(product, ~s|health_status = "unknown"|) == ["never_connected", "untagged"]
      assert run(product, ~s|health_status != "unknown"|) == ["connected", "tagged"]
    end

    test "health_status inequality includes devices with no health record", %{product: product} do
      assert run(product, ~s|health_status != "healthy"|) == ["connected", "never_connected", "untagged"]
    end

    test "connection_type contains", %{product: product} do
      assert run(product, ~s|connection_type contains "wifi"|) == ["connected"]
      assert run(product, ~s|connection_type contains "ethernet"|) == []
    end

    test "connection_type not_contains includes devices with no connection metadata", %{product: product} do
      assert run(product, ~s|connection_type not_contains "wifi"|) == ["never_connected", "tagged", "untagged"]
    end

    test "updates enabled/disabled", %{product: product} do
      assert run(product, ~s|updates = "enabled"|) == ["connected", "never_connected", "tagged"]
      assert run(product, ~s|updates = "disabled"|) == ["untagged"]
      assert run(product, ~s|updates != "enabled"|) == ["untagged"]
    end

    test "updates penalty-box", %{product: product} do
      assert run(product, ~s|updates = "penalty-box"|) == ["never_connected"]
      # devices with no penalty timeout are not in the penalty box
      assert run(product, ~s|updates != "penalty-box"|) == ["connected", "tagged", "untagged"]
    end

    test "alarm_status with/without", %{product: product} do
      assert run(product, ~s|alarm_status = "with"|) == ["tagged"]
      # empty alarms ("connected") and no health record ("never_connected"/"untagged") count as without
      assert run(product, ~s|alarm_status = "without"|) == ["connected", "never_connected", "untagged"]
    end

    test "alarm_status inequality maps to the complementary value", %{product: product} do
      assert run(product, ~s|alarm_status != "with"|) == ["connected", "never_connected", "untagged"]
      assert run(product, ~s|alarm_status != "without"|) == ["tagged"]
    end

    test "alarm matches devices carrying a specific alarm", %{product: product} do
      assert run(product, ~s|alarm contains "SomeAlarm"|) == ["tagged"]
    end

    test "alarm not_contains includes devices with no alarms or health record", %{product: product} do
      assert run(product, ~s|alarm not_contains "SomeAlarm"|) == ["connected", "never_connected", "untagged"]
    end

    test "update_status reflects whether a device has an inflight update", %{
      product: product,
      firmware: firmware,
      tagged: tagged
    } do
      {:ok, _} = Fixtures.inflight_update(tagged, firmware)

      assert run(product, ~s|update_status is "updating"|) == ["tagged"]
      assert run(product, ~s|update_status is "not updating"|) == ["connected", "never_connected", "untagged"]
      assert run(product, ~s|update_status is not "updating"|) == ["connected", "never_connected", "untagged"]
      assert run(product, ~s|update_status is not "not updating"|) == ["tagged"]
    end

    test "metric comparison uses each device's latest reading", %{
      product: product,
      tagged: tagged,
      connected: connected
    } do
      # "tagged" reads 40 (older) then 60 (latest); "connected" reads 30.
      save_metric(tagged, "cpu_temp", 40.0, 60)
      save_metric(tagged, "cpu_temp", 60.0, 10)
      save_metric(connected, "cpu_temp", 30.0, 10)

      assert run(product, ~s|metric:cpu_temp > 50|) == ["tagged"]
      assert run(product, ~s|metric:cpu_temp < 50|) == ["connected"]
      assert run(product, ~s|metric:cpu_temp >= 30|) == ["connected", "tagged"]
      # a metric key no device reports matches nothing
      assert run(product, ~s|metric:load_15min > 0|) == []
    end

    test "deleted matches the soft-deleted state", %{product: product, untagged: untagged} do
      {1, _} =
        Repo.update_all(where(Device, id: ^untagged.id),
          set: [deleted_at: DateTime.truncate(DateTime.utc_now(), :second)]
        )

      assert run(product, ~s|deleted = "true"|) == ["untagged"]
      assert run(product, ~s|deleted = "false"|) == ["connected", "never_connected", "tagged"]
      assert run(product, ~s|deleted != "true"|) == ["connected", "never_connected", "tagged"]
    end
  end
end
