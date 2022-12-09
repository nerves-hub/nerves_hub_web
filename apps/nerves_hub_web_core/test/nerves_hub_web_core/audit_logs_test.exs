defmodule NervesHubWebCore.AuditLogsTest do
  use NervesHubWebCore.DataCase, async: true
  alias NervesHubWebCore.AuditLogs
  alias NervesHubWebCore.Fixtures

  describe "truncate/1" do
    test "can truncate logs" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device_1 = Fixtures.device_fixture(org, product, firmware)
      device_2 = Fixtures.device_fixture(org, product, firmware)
      device_3 = Fixtures.device_fixture(org, product, firmware)

      now = ~U[2022-12-07 00:00:00Z]

      for i <- 1..10 do
        AuditLogs.audit!(device_1, device_1, :update, %{
          last_communication: DateTime.add(now, i)
        })
      end

      for i <- 1..8 do
        AuditLogs.audit!(device_2, device_2, :update, %{
          last_communication: DateTime.add(now, i)
        })
      end

      for i <- 1..5 do
        AuditLogs.audit!(device_3, device_3, :update, %{
          last_communication: DateTime.add(now, i)
        })
      end

      assert :ok =
               AuditLogs.truncate(
                 retain_per_resource: 5,
                 max_resources_per_run: 3,
                 max_records_per_resource_per_run: 3
               )

      assert 7 = device_1 |> AuditLogs.logs_for() |> length()
      assert 5 = device_2 |> AuditLogs.logs_for() |> length()
      assert 5 = device_3 |> AuditLogs.logs_for() |> length()
    end

    test "limited number of resources truncated per run" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device_1 = Fixtures.device_fixture(org, product, firmware)
      device_2 = Fixtures.device_fixture(org, product, firmware)
      device_3 = Fixtures.device_fixture(org, product, firmware)

      now = ~U[2022-12-07 00:00:00Z]

      for i <- 1..10 do
        AuditLogs.audit!(device_1, device_1, :update, %{
          last_communication: DateTime.add(now, i)
        })
      end

      for i <- 1..8 do
        AuditLogs.audit!(device_2, device_2, :update, %{
          last_communication: DateTime.add(now, i)
        })
      end

      for i <- 1..5 do
        AuditLogs.audit!(device_3, device_3, :update, %{
          last_communication: DateTime.add(now, i)
        })
      end

      assert :ok =
               AuditLogs.truncate(
                 retain_per_resource: 5,
                 max_resources_per_run: 1,
                 max_records_per_resource_per_run: 3
               )

      assert 7 = device_1 |> AuditLogs.logs_for() |> length()
      assert 8 = device_2 |> AuditLogs.logs_for() |> length()
      assert 5 = device_3 |> AuditLogs.logs_for() |> length()
    end
  end
end
