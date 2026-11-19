defmodule NervesHub.Products.ApiKeyActorTest do
  @moduledoc """
  What a product API key leaves behind when it does something a person could
  have done: the audit entry names the key, and columns that name a user stay
  empty.
  """

  use NervesHub.DataCase, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Updates
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo
  alias NervesHub.Scripts

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    api_key = Fixtures.api_key_fixture(product, user, %{"name" => "CI"})

    %{
      user: user,
      org: org,
      org_key: org_key,
      product: product,
      firmware: firmware,
      device: device,
      api_key: api_key,
      tmp_dir: tmp_dir
    }
  end

  defp descriptions_by(api_key), do: Enum.map(AuditLogs.logs_by(api_key), & &1.description)

  describe "a device" do
    test "can be rebooted by a key", %{device: device, api_key: api_key} do
      {:ok, _device} = DeviceEvents.reboot(device, api_key)

      assert "API key CI rebooted device #{device.identifier}" in descriptions_by(api_key)
    end

    test "can be sent firmware by a key", context do
      %{device: device, org_key: org_key, product: product, tmp_dir: tmp_dir, api_key: api_key} = context
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, _device} = DeviceEvents.manual_update(device, new_firmware, api_key)

      assert Enum.any?(descriptions_by(api_key), &(&1 =~ "API key CI pushed firmware"))
    end

    test "can be taken out of the penalty box by a key", %{device: device, api_key: api_key} do
      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      {:ok, cleared} = Updates.clear_penalty_box(device, api_key)

      refute cleared.updates_blocked_until

      assert "API key CI removed device #{device.identifier} from the penalty box" in descriptions_by(api_key)
    end

    test "can have its settings changed by a key", %{device: device, api_key: api_key} do
      {:ok, updated} = Devices.update_device_settings(device, %{"description" => "from ci"}, api_key)

      assert updated.description == "from ci"
      assert "API key CI updated device #{device.identifier}" in descriptions_by(api_key)
    end
  end

  describe "a deployment group" do
    test "records the key that created it, on the group and its first release", context do
      %{product: product, firmware: firmware, api_key: api_key} = context
      params = %{name: "from ci", conditions: %{version: "< 1.0.0", tags: ["beta"]}}

      {:ok, deployment_group} = ManagedDeployments.create_deployment_group(params, product, firmware, api_key)

      assert [release] = ManagedDeployments.list_deployment_releases(deployment_group)
      assert release.created_by_api_key.id == api_key.id
      assert is_nil(release.created_by)

      assert "API key CI created deployment group from ci" in descriptions_by(api_key)
    end

    test "records the key on a later release", context do
      %{org_key: org_key, product: product, firmware: firmware, tmp_dir: tmp_dir, user: user, api_key: api_key} =
        context

      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, {release, _group}} =
        ManagedDeployments.create_deployment_release(deployment_group, new_firmware, nil, api_key, %{})

      assert release.created_by_api_key_id == api_key.id
      assert is_nil(release.created_by_id)
    end

    test "refuses a key from another product", context do
      %{org: org, org_key: org_key, product: product, firmware: firmware, tmp_dir: tmp_dir, user: user} = context

      other_product = Fixtures.product_fixture(user, org, %{name: "other"})
      other_key = Fixtures.api_key_fixture(other_product, user)

      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      assert {:error, changeset} =
               ManagedDeployments.create_deployment_release(deployment_group, new_firmware, nil, other_key, %{})

      assert {"belongs to another product", _} = changeset.errors[:created_by_api_key]
    end
  end

  describe "firmware" do
    test "deleted by a key leaves deleted_by empty", context do
      %{org_key: org_key, product: product, tmp_dir: tmp_dir, api_key: api_key} = context
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      assert {:ok, deleted} = Firmwares.delete_firmware(firmware, api_key)

      assert deleted.deleted_at
      assert is_nil(deleted.deleted_by_id)
    end
  end

  describe "support scripts" do
    test "can be created, updated and deleted by a key, with the key in the log", context do
      %{product: product, api_key: api_key} = context

      {:ok, script} = Scripts.create(product, api_key, %{name: "MOTD", text: "NervesMOTD.print()"})
      assert is_nil(script.created_by_id)

      {:ok, script} = Scripts.update(script, api_key, %{name: "New name"})
      assert is_nil(script.last_updated_by_id)

      {:ok, _script} = Scripts.delete(script.id, product, api_key)

      descriptions = descriptions_by(api_key)
      assert length(descriptions) == 3
      assert Enum.all?(descriptions, &String.starts_with?(&1, "API key CI "))
    end
  end

  describe "a device created by a key" do
    test "gets a shared secret with no user against it", context do
      %{product: product, api_key: api_key} = context

      Mimic.stub(NervesHub.DeviceLink, :shared_secrets_enabled?, fn -> true end)

      assert {:ok, {device, auth}} =
               Devices.create_device_with_shared_secret_auth(product, %{"identifier" => "from-ci"}, api_key)

      assert device.identifier == "from-ci"
      assert is_nil(Repo.reload!(auth).created_by_id)
      assert Enum.any?(descriptions_by(api_key), &(&1 =~ "API key CI"))
    end
  end
end
