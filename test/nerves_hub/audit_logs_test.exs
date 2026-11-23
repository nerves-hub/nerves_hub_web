defmodule NervesHub.AuditLogsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  describe "truncate" do
    test "delete audit log entries older than 3 days" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)

      Fixtures.add_audit_logs(10, org.id, 10)

      assert {:ok, 7} = AuditLogs.truncate(org.id, 3)

      assert Repo.aggregate(AuditLog, :count) == 3
    end

    test "delete audit log entries older than 8 days" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)

      Fixtures.add_audit_logs(10, org.id, 10)

      assert {:ok, 2} = AuditLogs.truncate(org.id, 8)

      assert Repo.aggregate(AuditLog, :count) == 8
    end

    test "only deletes audit log from the specified org" do
      user = Fixtures.user_fixture()

      org = Fixtures.org_fixture(user)
      org2 = Fixtures.org_fixture(user, %{name: "Test-Org2"})

      Fixtures.add_audit_logs(10, org.id, 10)
      Fixtures.add_audit_logs(100, org2.id, 10)

      assert {:ok, 7} = AuditLogs.truncate(org.id, 3)

      assert Repo.aggregate(AuditLog, :count) == 13
    end
  end

  describe "kind" do
    setup do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)

      %{user: user, org: org}
    end

    test "is stored when given", %{user: user, org: org} do
      :ok = AuditLogs.audit!(user, org, "rebooted", kind: :device_rebooted)

      assert [%AuditLog{kind: :device_rebooted}] = AuditLogs.logs_for(org)
    end

    test "is nil when not given, as on rows written before kinds", %{user: user, org: org} do
      :ok = AuditLogs.audit!(user, org, "did something")

      assert [%AuditLog{kind: nil}] = AuditLogs.logs_for(org)
    end

    test "is kept beside a reference id", %{user: user, org: org} do
      ref = Ecto.UUID.generate()

      AuditLogs.audit_with_ref!(user, org, "sent an archive", ref, kind: :archive_sent)

      assert [%AuditLog{kind: :archive_sent, reference_id: ^ref}] = AuditLogs.logs_for(org)
    end

    test "rejects a kind it doesn't know", %{user: user, org: org} do
      changeset = user |> AuditLog.build(org, "did something", kind: :made_up) |> AuditLog.changeset()

      refute changeset.valid?
      assert {_, error} = changeset.errors[:kind]
      assert error[:validation] == :inclusion
    end
  end

  describe "actor_devices/1" do
    setup do
      Fixtures.standard_fixture()
    end

    test "loads the devices that wrote the entries, keyed by id", context do
      %{user: user, device: device, deployment_group: deployment_group} = context

      :ok = AuditLogs.audit!(user, deployment_group, "User did something")
      :ok = AuditLogs.audit!(device, deployment_group, "Device did something")
      :ok = AuditLogs.audit!(deployment_group, deployment_group, "Group did something")

      assert deployment_group |> AuditLogs.logs_for() |> AuditLogs.actor_devices() == %{
               device.id => %{identifier: device.identifier, deleted?: false}
             }
    end

    test "marks a deleted device", %{device: device, deployment_group: deployment_group} do
      :ok = AuditLogs.audit!(device, deployment_group, "Device did something")
      {:ok, _} = NervesHub.Devices.delete_device(device)

      device_id = device.id

      assert %{^device_id => %{deleted?: true}} =
               deployment_group |> AuditLogs.logs_for() |> AuditLogs.actor_devices()
    end
  end

  describe "load_references/3" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      Fixtures.standard_fixture(tmp_dir)
    end

    test "loads the records an entry names, under their current names", %{
      user: user,
      org: org,
      device: device,
      deployment_group: group,
      firmware: firmware
    } do
      :ok = DeviceTemplates.audit_device_deployment_group_update_triggered(device, group, firmware)
      :ok = DeviceTemplates.audit_reboot(user, device)

      Repo.update!(Ecto.Changeset.change(user, name: "Renamed"))

      references = AuditLogs.load_references(AuditLogs.logs_for(device), org, user)

      assert %{name: "Renamed"} = references[{"user", user.id}]
      assert %{identifier: identifier, product: %{}} = references[{"device", device.id}]
      assert identifier == device.identifier
      assert %{id: group_id, product: %{}} = references[{"deployment_group", group.id}]
      assert group_id == group.id
      assert %{uuid: uuid} = references[{"firmware", firmware.uuid}]
      assert uuid == firmware.uuid
    end

    test "leaves out a user who is no longer a member of the org", %{user: user, org: org, device: device} do
      other = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, other, %{role: :view})
      :ok = DeviceTemplates.audit_reboot(other, device)
      :ok = Accounts.remove_org_user(org, other)

      references = AuditLogs.load_references(AuditLogs.logs_for(device), org, user)

      refute Map.has_key?(references, {"user", other.id})
    end

    test "leaves out a deleted device", %{user: user, org: org, device: device} do
      :ok = DeviceTemplates.audit_reboot(user, device)
      logs = AuditLogs.logs_for(device)
      {:ok, _} = Devices.delete_device(device)

      refute Map.has_key?(AuditLogs.load_references(logs, org, user), {"device", device.id})
    end

    test "leaves out a device a custom role's tags don't match", %{user: user, org: org, device: device} do
      :ok = DeviceTemplates.audit_reboot(user, device)

      role = Fixtures.org_role_fixture(org, %{device_tags: ["support"]})
      {:ok, org_user} = Accounts.get_org_user(org, user)
      {:ok, _} = Accounts.change_org_user_role(org_user, role)

      references = AuditLogs.load_references(AuditLogs.logs_for(device), org, user)

      refute Map.has_key?(references, {"device", device.id})
    end

    test "never loads a record from another org", %{user: user, device: device} do
      :ok = DeviceTemplates.audit_reboot(user, device)
      other_org = Fixtures.org_fixture(user, %{name: "Other-Org"})

      refute Map.has_key?(AuditLogs.load_references(AuditLogs.logs_for(device), other_org, user), {"device", device.id})
    end

    test "an entry written without a template names nothing", %{user: user, org: org, device: device} do
      :ok = AuditLogs.audit!(user, device, "User #{user.name} did something")

      assert AuditLogs.load_references(AuditLogs.logs_for(device), org, user) == %{}
    end
  end

  describe "an entry written from a template" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      Fixtures.standard_fixture(tmp_dir)
    end

    test "keeps the template and its values beside the text they make", %{user: user, device: device} do
      :ok = DeviceTemplates.audit_script_run(user, device, "Collect logs", "Slack")

      assert [log] = AuditLogs.logs_for(device)

      assert log.description ==
               "#{user.name} ran support script Collect logs on device #{device.identifier} from Slack"

      assert log.template == "%{actor} ran support script %{script} on device %{resource} from %{via}"

      assert log.template_values == %{
               "actor" => %{"type" => "user", "id" => user.id, "name" => user.name},
               "resource" => %{"type" => "device", "id" => device.id, "name" => device.identifier},
               "script" => "Collect logs",
               "via" => "Slack"
             }
    end
  end
end
