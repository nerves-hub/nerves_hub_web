defmodule NervesHub.DevicesTest do
  use NervesHub.DataCase, async: false
  use Mimic

  alias Ecto.Changeset

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Products

  alias NervesHub.Repo

  alias Phoenix.Socket.Broadcast

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment_group = Fixtures.deployment_group_fixture(org, firmware, %{is_active: true})
    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})
    device2 = Fixtures.device_fixture(org, product, firmware)
    device3 = Fixtures.device_fixture(org, product, firmware)
    ca_fix = Fixtures.ca_certificate_fixture(org)
    %{db_cert: db_cert} = Fixtures.device_certificate_fixture(device)

    cert =
      X509.PrivateKey.new_ec(:secp256r1)
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("/CN=#{device.identifier}", ca_fix.cert, ca_fix.key)

    {:ok,
     %{
       cert: cert,
       db_cert: db_cert,
       user: user,
       org: org,
       org_key: org_key,
       firmware: firmware,
       device: device,
       device2: device2,
       device3: device3,
       deployment_group: deployment_group,
       product: product
     }}
  end

  test "create_device with valid parameters", %{
    org: org,
    product: product,
    firmware: firmware
  } do
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)

    params = %{
      org_id: org.id,
      product_id: product.id,
      firmware_metadata: metadata,
      identifier: "valid identifier"
    }

    {:ok, %Devices.Device{} = device} = Devices.create_device(params)

    for key <- Map.keys(metadata) do
      assert Map.get(device.firmware_metadata, key) == Map.get(metadata, key)
    end
  end

  test "delete_device", %{org: org, device: device} do
    {:ok, _device} = Devices.delete_device(device)

    assert {:error, _} = Devices.get_device_by_org(org, device.id)
  end

  test "destroy_device", %{device: device} do
    {:ok, _} =
      Devices.save_device_health(%{
        "device_id" => device.id,
        "data" => %{},
        "status" => :healthy,
        "status_reasons" => %{}
      })

    {:ok, _device} = Devices.destroy_device(device)

    assert is_nil(Repo.get(Device, device.id))
    refute Repo.exists?(where(DeviceHealth, device_id: ^device.id))
  end

  test "can tag multiple devices", %{
    user: user,
    device: device,
    device2: device2,
    device3: device3
  } do
    devices = [device, device2, device3]
    tags = "New,Tags"

    %{ok: devices} = Devices.tag_devices(devices, user, tags)

    assert Enum.all?(devices, fn device -> device.tags == ["New", "Tags"] end)
  end

  test "can disable updates for multiple devices", %{
    user: user,
    device: device,
    device2: device2,
    device3: device3
  } do
    devices = [device, device2, device3]

    %{ok: devices} = Devices.disable_updates_for_devices(devices, user)

    assert Enum.all?(devices, fn device -> device.updates_enabled == false end)
  end

  test "can enable updates for a devices" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user, %{name: "Test-Org-2"})
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware, %{updates_enabled: false})

    :ok = Devices.update_attempted(device)
    {:ok, device} = Devices.enable_updates(device, user)

    assert device.updates_enabled
    assert device.update_attempts == []
  end

  test "can enable updates for multiple devices" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user, %{name: "Test-Org-2"})
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware, %{updates_enabled: false})
    device2 = Fixtures.device_fixture(org, product, firmware, %{updates_enabled: false})
    device3 = Fixtures.device_fixture(org, product, firmware, %{updates_enabled: false})

    devices = [device, device2, device3]

    %{ok: devices} = Devices.enable_updates_for_devices(devices, user)

    assert Enum.all?(devices, fn device -> device.updates_enabled == true end)
  end

  test "can clear penalty box for multiple devices" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user, %{name: "Test-Org-2"})
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)

    device =
      Fixtures.device_fixture(org, product, firmware, %{updates_blocked_until: DateTime.utc_now()})

    device2 =
      Fixtures.device_fixture(org, product, firmware, %{updates_blocked_until: DateTime.utc_now()})

    device3 =
      Fixtures.device_fixture(org, product, firmware, %{updates_blocked_until: DateTime.utc_now()})

    devices = [device, device2, device3]

    %{ok: devices} = Devices.clear_penalty_box_for_devices(devices, user)

    assert Enum.all?(devices, fn device -> is_nil(device.updates_blocked_until) end)
  end

  test "delete_device deletes its certificates", %{device: device} do
    [_cert] = Devices.get_device_certificates(device)

    {:ok, _device} = Devices.delete_device(device)
    assert [] = Devices.get_device_certificates(device)
  end

  test "create_device with invalid parameters", %{firmware: firmware} do
    params = %{
      identifier: "valid identifier",
      architecture: firmware.architecture,
      platform: firmware.platform
    }

    assert {:error, %Changeset{}} = Devices.create_device(params)
  end

  test "cannot create two devices with the same identifier", %{
    org: org,
    product: product,
    firmware: firmware
  } do
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)

    params = %{
      org_id: org.id,
      product_id: product.id,
      firmware_metadata: metadata,
      identifier: "valid identifier"
    }

    assert {:ok, %Devices.Device{}} = Devices.create_device(params)
    assert {:error, %Ecto.Changeset{}} = Devices.create_device(params)
  end

  test "create device certificate", %{device: device, cert: cert} do
    now = DateTime.utc_now()
    device_id = device.id

    params = %{
      serial: "12345",
      not_before: now,
      not_after: now,
      device_id: device_id,
      aki: "1234",
      ski: "5678",
      der: X509.Certificate.to_der(cert)
    }

    assert {:ok, %DeviceCertificate{device_id: ^device_id}} =
             Devices.create_device_certificate(device, params)
  end

  test "create device certificate without subject key id", %{device: device, cert: cert} do
    now = DateTime.utc_now()
    device_id = device.id

    params = %{
      serial: "12345",
      not_before: now,
      not_after: now,
      device_id: device_id,
      aki: "1234",
      der: X509.Certificate.to_der(cert)
    }

    assert {:ok, %DeviceCertificate{device_id: ^device_id}} =
             Devices.create_device_certificate(device, params)
  end

  test "select one device when it has two certificates", %{
    device: device,
    db_cert: db_cert,
    cert: cert
  } do
    now = DateTime.utc_now()

    params = %{
      serial: "67890",
      not_before: now,
      not_after: now,
      aki: "1234",
      ski: "5678",
      der: X509.Certificate.to_der(cert)
    }

    expected_id = device.id

    assert {:ok, %DeviceCertificate{} = db_cert2} =
             Devices.create_device_certificate(device, params)

    assert {:ok, %{id: ^expected_id}} = Devices.get_device_by_certificate(db_cert2)
    assert {:ok, %{id: ^expected_id}} = Devices.get_device_by_certificate(db_cert)
  end

  test "cannot create device certificates with duplicate serial numbers", %{
    device: device,
    cert: cert
  } do
    now = DateTime.utc_now()

    params = %{
      serial: "12345",
      not_before: now,
      not_after: now,
      device_id: device.id,
      aki: "1234",
      ski: "5678",
      der: X509.Certificate.to_der(cert)
    }

    assert {:ok, %DeviceCertificate{}} = Devices.create_device_certificate(device, params)
    assert {:error, %Changeset{}} = Devices.create_device_certificate(device, params)
  end

  test "cannot create device certificates with invalid parameters", %{device: device} do
    params = %{
      serial: "12345",
      device_id: device.id
    }

    assert {:error, %Changeset{}} = Devices.create_device_certificate(device, params)
  end

  test "create ca certificate with valid params", %{org: org} do
    org_id = org.id

    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)

    {not_before, not_after} = NervesHub.Certificate.get_validity(ca)

    params = %{
      serial: NervesHub.Certificate.get_serial_number(ca),
      aki: NervesHub.Certificate.get_aki(ca),
      ski: NervesHub.Certificate.get_ski(ca),
      not_before: not_before,
      not_after: not_after,
      der: X509.Certificate.to_der(ca)
    }

    assert {:ok, %CACertificate{org_id: ^org_id}} = Devices.create_ca_certificate(org, params)
  end

  test "cannot create ca certificates with duplicate serial numbers", %{org: org} do
    org_id = org.id

    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)

    {not_before, not_after} = NervesHub.Certificate.get_validity(ca)

    params = %{
      serial: NervesHub.Certificate.get_serial_number(ca),
      aki: NervesHub.Certificate.get_aki(ca),
      ski: NervesHub.Certificate.get_ski(ca),
      not_before: not_before,
      not_after: not_after,
      der: X509.Certificate.to_der(ca)
    }

    assert {:ok, %CACertificate{org_id: ^org_id}} = Devices.create_ca_certificate(org, params)
    assert {:error, %Changeset{}} = Devices.create_ca_certificate(org, params)
  end

  test "can get certificate by aki", %{org: org} do
    org_id = org.id

    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)

    {not_before, not_after} = NervesHub.Certificate.get_validity(ca)

    serial = NervesHub.Certificate.get_serial_number(ca)
    aki = NervesHub.Certificate.get_aki(ca)

    params = %{
      serial: serial,
      aki: aki,
      ski: NervesHub.Certificate.get_ski(ca),
      not_before: not_before,
      not_after: not_after,
      der: X509.Certificate.to_der(ca)
    }

    assert {:ok, %CACertificate{org_id: ^org_id}} = Devices.create_ca_certificate(org, params)
    assert {:ok, %CACertificate{serial: ^serial}} = Devices.get_ca_certificate_by_aki(aki)
  end

  test "get_device_by_identifier with existing device", %{org: org, device: target_device} do
    assert {:ok, result} = Devices.get_device_by_identifier(org, target_device.identifier)

    for key <- [:org_id, :deployment_id, :device_identifier] do
      assert Map.get(target_device, key) == Map.get(result, key)
    end
  end

  test "get_device_by_identifier without existing device", %{org: org} do
    assert {:error, :not_found} = Devices.get_device_by_identifier(org, "non existing identifier")
  end

  test "matches_deployment_group? works when device and/or deployment tags are nil", %{
    deployment_group: deployment_group,
    device: device
  } do
    # There is a version check before the tags, so load both versions
    # here to ensure they match and we get to the tag check
    device = put_in(device.firmware_metadata.version, "1.0.0")
    deployment_group = put_in(deployment_group.conditions["version"], "1.0.0")

    nil_tags_deployment_group = put_in(deployment_group.conditions["tags"], nil)

    refute Devices.matches_deployment_group?(%{device | tags: nil}, deployment_group)
    assert Devices.matches_deployment_group?(%{device | tags: nil}, nil_tags_deployment_group)
    assert Devices.matches_deployment_group?(device, nil_tags_deployment_group)
  end

  test "create shared secret auth with associated product shared secret auth", context do
    {:ok, %{id: product_ssa_id}} = Products.create_shared_secret_auth(context.product)

    assert {:ok, auth} =
             Devices.create_shared_secret_auth(context.device, %{
               product_shared_secret_auth_id: product_ssa_id
             })

    assert auth.product_shared_secret_auth_id == product_ssa_id
  end

  describe "tracking update attempts and verifying eligibility" do
    test "records the timestamp of an attempt", %{device: device} do
      :ok = Devices.update_attempted(device)
      device = Repo.reload(device)
      assert Enum.count(device.update_attempts) == 1

      :ok = Devices.update_attempted(device)
      device = Repo.reload(device)
      assert Enum.count(device.update_attempts) == 2
    end

    test "records and audit log for updating", %{device: device} do
      assert [] = AuditLogs.logs_for(device)

      :ok = Devices.update_attempted(device)

      [audit_log] = AuditLogs.logs_for(device)

      assert audit_log.description =~ ~r/attempting to update/
    end

    test "resets update attempts on successful update", %{device: device} do
      :ok = Devices.update_attempted(device)
      device = Repo.reload(device)
      assert Enum.count(device.update_attempts) == 1

      {:ok, device} = Devices.firmware_update_successful(device, device.firmware_metadata)
      assert Enum.empty?(device.update_attempts)
    end

    test "clears an inflight update if it matches", %{
      device: device,
      deployment_group: deployment_group
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, inflight_update} = Devices.told_to_update(device, deployment_group)

      {:ok, _device} = Devices.firmware_update_successful(device, device.firmware_metadata)

      inflight_update = Repo.reload(inflight_update)
      assert is_nil(inflight_update)
    end

    test "increments the deployment's updated count", %{
      device: device,
      deployment_group: deployment_group
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      assert deployment_group.current_updated_devices == 0

      {:ok, _inflight_update} = Devices.told_to_update(device, deployment_group)

      {:ok, _device} = Devices.firmware_update_successful(device, device.firmware_metadata)

      deployment_group = Repo.reload(deployment_group)
      assert deployment_group.current_updated_devices == 1
    end

    test "reverts device.priority_updates to false", %{device: device} do
      {:ok, device} = Devices.update_device(device, %{priority_updates: true})
      assert device.priority_updates

      {:ok, device} = Devices.firmware_update_successful(device, device.firmware_metadata)
      refute device.priority_updates
    end

    test "device updates successfully", %{device: device, deployment_group: deployment_group} do
      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      :ok = Devices.update_attempted(device)

      {:ok, device} = Devices.verify_update_eligibility(device, deployment_group)

      assert device.updates_enabled
      refute device.updates_blocked_until
    end

    test "device updates successfully after a few attempts", %{
      device: device,
      deployment_group: deployment_group
    } do
      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      :ok = Devices.update_attempted(device)
      :ok = Devices.update_attempted(device)

      device = Repo.reload(device)

      {:ok, device} = Devices.verify_update_eligibility(device, deployment_group)

      assert device.updates_enabled
      refute device.updates_blocked_until
    end

    test "device updates successfully after a few attempts over a long period of time", state do
      %{device: device, deployment_group: deployment_group} = state

      deployment_group = %{
        deployment_group
        | device_failure_threshold: 6,
          device_failure_rate_amount: 3
      }

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      now = DateTime.utc_now()

      :ok = Devices.update_attempted(device, DateTime.add(now, -3600, :second))
      :ok = Devices.update_attempted(device, DateTime.add(now, -1200, :second))
      :ok = Devices.update_attempted(device, now)

      device = Repo.reload(device)

      {:ok, device} = Devices.verify_update_eligibility(device, deployment_group)

      assert device.updates_enabled
      refute device.updates_blocked_until
    end

    test "device already matches the firmware of the deployment", state do
      %{device: device, deployment_group: deployment_group} = state

      {:error, :up_to_date, _device} = Devices.verify_update_eligibility(device, deployment_group)
    end

    test "device should be rejected for updates based on threshold rate and have it's inflight updates cleared",
         state do
      %{device: device, deployment_group: deployment_group} = state
      deployment_group = %{deployment_group | device_failure_threshold: 6}
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())
      {:ok, _inflight_update} = Devices.told_to_update(device, deployment_group)

      now = DateTime.utc_now()

      :ok = Devices.update_attempted(device, DateTime.add(now, -3600, :second))
      :ok = Devices.update_attempted(device, DateTime.add(now, -1200, :second))
      :ok = Devices.update_attempted(device, DateTime.add(now, -500, :second))
      :ok = Devices.update_attempted(device, DateTime.add(now, -500, :second))
      :ok = Devices.update_attempted(device, DateTime.add(now, -500, :second))
      :ok = Devices.update_attempted(device, now)

      device = Repo.reload(device)

      {:error, :updates_blocked, device} =
        Devices.verify_update_eligibility(device, deployment_group)

      assert device.updates_blocked_until
      assert device.update_attempts == []
      assert Devices.count_inflight_updates_for(deployment_group) == 0
    end

    test "device should be rejected for updates based on attempt rate and have it's inflight updates cleared",
         state do
      %{device: device, deployment_group: deployment_group} = state
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())
      {:ok, _inflight_update} = Devices.told_to_update(device, deployment_group)

      now = DateTime.utc_now()

      :ok = Devices.update_attempted(device, DateTime.add(now, -13, :second))
      :ok = Devices.update_attempted(device, DateTime.add(now, -10, :second))
      :ok = Devices.update_attempted(device, DateTime.add(now, -5, :second))
      :ok = Devices.update_attempted(device, DateTime.add(now, -2, :second))
      :ok = Devices.update_attempted(device, now)

      device = Repo.reload(device)

      {:error, :updates_blocked, device} =
        Devices.verify_update_eligibility(device, deployment_group)

      assert device.updates_blocked_until
      assert device.update_attempts == []
      assert Devices.count_inflight_updates_for(deployment_group) == 0
    end

    test "device in penalty box should be rejected for updates and have it's inflight updates cleared",
         state do
      %{device: device, deployment_group: deployment_group} = state
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      now = DateTime.utc_now()

      # future time
      device = %{device | updates_blocked_until: DateTime.add(now, 1, :second)}
      {:ok, _inflight_update} = Devices.told_to_update(device, deployment_group)

      {:error, :updates_blocked, _device} =
        Devices.verify_update_eligibility(device, deployment_group, now)

      assert Devices.count_inflight_updates_for(deployment_group) == 0

      # now
      device = %{device | updates_blocked_until: now}
      {:ok, _device} = Devices.verify_update_eligibility(device, deployment_group, now)

      # past time
      device = %{device | updates_blocked_until: DateTime.add(now, -1, :second)}
      {:ok, _device} = Devices.verify_update_eligibility(device, deployment_group, now)
    end
  end

  describe "told_to_update/2" do
    test "update payload uses the default firmware url", %{device: device, deployment_group: deployment_group} do
      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      deployment_group = Repo.preload(deployment_group, :org)

      topic = "device:#{device.id}"
      Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)

      {:ok, _inflight_update} = Devices.told_to_update(device, deployment_group)

      # check that the first device was told to update
      assert_receive %Broadcast{
                       topic: ^topic,
                       event: "update",
                       payload: %{
                         firmware_url: firmware_url
                       }
                     },
                     500

      assert String.starts_with?(firmware_url, "http://localhost:1234")
    end

    test "update payload uses the Orgs `firmware_proxy_url` setting", %{
      device: device,
      deployment_group: deployment_group
    } do
      Org
      |> where(id: ^deployment_group.org_id)
      |> Repo.update_all(set: [settings: %Org.Settings{firmware_proxy_url: "https://files.customer.com/download"}])

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      deployment_group = Repo.preload(deployment_group, :org)

      topic = "device:#{device.id}"
      Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)

      {:ok, _inflight_update} = Devices.told_to_update(device, deployment_group)

      # check that the first device was told to update
      assert_receive %Broadcast{
                       topic: ^topic,
                       event: "update",
                       payload: %{
                         firmware_url: firmware_url
                       }
                     },
                     500

      assert String.starts_with?(firmware_url, "https://files.customer.com/download?firmware=")
    end
  end

  describe "inflight updates" do
    test "clears expired inflight updates", %{device: device, deployment_group: deployment_group} do
      deployment_group = Repo.preload(deployment_group, :firmware)
      Fixtures.inflight_update(device, deployment_group)
      assert {0, _} = Devices.delete_expired_inflight_updates()

      Devices.clear_inflight_update(device)

      expires_at =
        DateTime.utc_now()
        |> DateTime.shift(hour: -1)
        |> DateTime.truncate(:second)

      Fixtures.inflight_update(device, deployment_group, %{"expires_at" => expires_at})
      assert {1, _} = Devices.delete_expired_inflight_updates()
    end
  end

  defp update_firmware_uuid(device, uuid) do
    firmware_metadata = %{
      architecture: "x86_64",
      platform: "platform",
      product: "valid product",
      version: "1.0.0",
      uuid: uuid
    }

    Devices.update_firmware_metadata(device, firmware_metadata, :unknown, false)
  end

  describe "device health reports" do
    test "create new device health", %{device: device} do
      device_health = %{"device_id" => device.id, "data" => %{"literally_any_map" => "values"}}

      assert {:ok, %Devices.DeviceHealth{id: health_id}} =
               Devices.save_device_health(device_health)

      assert %Devices.DeviceHealth{} = Devices.get_latest_health(device.id)

      # Assert device is updated with latest health
      assert %{latest_health_id: ^health_id} = Devices.get_device(device.id)
    end
  end

  describe "update_deployment_group/2" do
    test "updates deployment and broadcasts 'devices/deployment-updated'", %{
      device: device,
      deployment_group: deployment_group
    } do
      refute device.deployment_id

      NervesHubWeb.Endpoint.subscribe("device:#{device.id}")
      device = Devices.update_deployment_group(device, deployment_group)

      assert device.deployment_id == deployment_group.id
      assert_receive %{event: "deployment_updated"}
    end
  end

  describe "clear_deployment_group/2" do
    test "clears deployment and broadcasts 'devices/deployment-cleared'", %{
      device: device,
      deployment_group: deployment_group
    } do
      device = Devices.update_deployment_group(device, deployment_group)

      NervesHubWeb.Endpoint.subscribe("device:#{device.id}")
      device = Devices.clear_deployment_group(device)

      refute device.deployment_id
      assert_receive %{event: "deployment_updated"}
    end
  end

  describe "available_for_update/2" do
    test "when deployment_group.queue_management is set to FIFO", %{
      deployment_group: deployment_group,
      device: device1 = %{id: device1_id},
      org: org,
      product: product
    } do
      assert deployment_group.queue_management == :FIFO

      device2 =
        %{id: device2_id} =
        Fixtures.device_fixture(org, product, deployment_group.firmware, %{priority_updates: true})

      device3 =
        %{id: device3_id} =
        Fixtures.device_fixture(org, product, deployment_group.firmware, %{priority_updates: true})

      device4 =
        %{id: device4_id} =
        Fixtures.device_fixture(org, product, deployment_group.firmware)

      Enum.with_index([device1, device2, device3, device4], fn device, index ->
        %{id: latest_connection_id} =
          DeviceConnection.create_changeset(%{
            product_id: product.id,
            device_id: device.id,
            established_at: DateTime.utc_now() |> DateTime.add(index + 1, :minute),
            last_seen_at: DateTime.utc_now(),
            status: :connected
          })
          |> Repo.insert!()

        Device
        |> where(id: ^device.id)
        |> Repo.update_all(set: [latest_connection_id: latest_connection_id])

        {:ok, device} =
          Devices.update_firmware_metadata(
            device,
            Map.from_struct(%{
              device.firmware_metadata
              | uuid: UUIDv7.autogenerate()
            }),
            :unknown,
            false
          )

        {:ok, _} = Devices.update_device(device, %{deployment_id: deployment_group.id})
      end)

      assert [%{id: ^device2_id}, %{id: ^device3_id}, %{id: ^device1_id}, %{id: ^device4_id}] =
               Devices.available_for_update(deployment_group, 10)
    end

    test "when deployment_group.queue_management is set to LIFO",
         %{
           deployment_group: deployment_group,
           device: device1 = %{id: device1_id},
           org: org,
           product: product
         } do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{
          enable_priority_updates: true
        })

      {:ok, device1} = Devices.update_device(device1, %{first_seen_at: DateTime.utc_now()})

      device2 =
        %{id: device2_id} =
        Fixtures.device_fixture(org, product, deployment_group.firmware, %{
          priority_updates: true,
          first_seen_at: DateTime.utc_now() |> DateTime.add(-1, :day)
        })

      device3 =
        %{id: device3_id} =
        Fixtures.device_fixture(org, product, deployment_group.firmware, %{
          priority_updates: true,
          first_seen_at: DateTime.utc_now() |> DateTime.add(-7, :day)
        })

      device4 =
        %{id: device4_id} =
        Fixtures.device_fixture(org, product, deployment_group.firmware, %{
          first_seen_at: DateTime.utc_now() |> DateTime.add(-3, :day)
        })

      Enum.each([device1, device2, device3, device4], fn device ->
        %{id: latest_connection_id} =
          DeviceConnection.create_changeset(%{
            product_id: product.id,
            device_id: device.id,
            established_at: DateTime.utc_now(),
            last_seen_at: DateTime.utc_now(),
            status: :connected
          })
          |> Repo.insert!()

        Device
        |> where(id: ^device.id)
        |> Repo.update_all(set: [latest_connection_id: latest_connection_id])

        {:ok, device} =
          Devices.update_firmware_metadata(
            device,
            Map.from_struct(%{
              device.firmware_metadata
              | uuid: UUIDv7.autogenerate()
            }),
            :unknown,
            false
          )

        {:ok, _} = Devices.update_device(device, %{deployment_id: deployment_group.id})
      end)

      assert [%{id: ^device2_id}, %{id: ^device3_id}, %{id: ^device1_id}, %{id: ^device4_id}] =
               Devices.available_for_update(%{deployment_group | queue_management: :LIFO}, 10)
    end
  end

  describe "resolve_update/1" do
    test "returns a delta firmware url if it exists", %{
      org: org,
      user: user,
      product: product,
      tmp_dir: tmp_dir
    } do
      new_org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      old_firmware =
        Fixtures.firmware_fixture(new_org_key, product, %{
          fwup_version: "1.13.0",
          dir: tmp_dir
        })
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      new_firmware =
        Fixtures.firmware_fixture(new_org_key, product, %{
          fwup_version: "1.13.0",
          dir: tmp_dir
        })
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      deployment_group =
        Fixtures.deployment_group_fixture(org, new_firmware, %{
          name: "Delta deployment updates",
          is_active: true,
          delta_updatable: true
        })
        |> Repo.preload(:firmware)

      device =
        Fixtures.device_fixture(org, product, old_firmware, %{
          status: :provisioned,
          deployment_id: deployment_group.id,
          fwup_version: "1.13.0"
        })
        |> Repo.preload(:deployment_group)

      delta = Fixtures.firmware_delta_fixture(old_firmware, new_firmware)

      {:ok, delta_url} = Firmwares.get_firmware_url(delta)

      update_payload = Devices.resolve_update(device)

      assert delta_url == update_payload.firmware_url
    end

    test "returns a delta firmware url if it exists for the product the device belongs to", %{
      user: user,
      tmp_dir: tmp_dir
    } do
      # two orgs which the same user belongs to
      {:ok, org_one} = Accounts.create_org(user, %{name: "One-Org"})
      {:ok, org_two} = Accounts.create_org(user, %{name: "Two-Org"})

      org_key_one = Fixtures.org_key_fixture(org_one, user, tmp_dir)
      org_key_two = Fixtures.org_key_fixture(org_two, user, tmp_dir)

      # two products with the same name
      {:ok, product_one} =
        Products.create_product(%{org_id: org_one.id, name: "Same Product Name"})

      {:ok, _product_two} =
        Products.create_product(%{org_id: org_two.id, name: "Same Product Name"})

      # create some firmware which can be uploaded to each org
      {:ok, _} =
        NervesHub.Support.Fwup.create_firmware(tmp_dir, "old-firmware", %{
          product: "Same Product Name",
          fwup_version: "1.13.0"
        })

      # sign and upload for org one
      {:ok, signed_firmware_one} =
        NervesHub.Support.Fwup.sign_firmware(
          tmp_dir,
          org_key_one.name,
          "old-firmware",
          "old-firmware-signed-one"
        )

      {:ok, old_firmware_one} = Firmwares.create_firmware(org_one, signed_firmware_one)

      old_firmware_one
      |> Ecto.Changeset.change(delta_updatable: true)
      |> Repo.update!()

      # sign and upload for org two
      {:ok, old_signed_firmware_two} =
        NervesHub.Support.Fwup.sign_firmware(
          tmp_dir,
          org_key_two.name,
          "old-firmware",
          "old-firmware-signed-two"
        )

      {:ok, old_firmware_two} = Firmwares.create_firmware(org_two, old_signed_firmware_two)

      old_firmware_two
      |> Ecto.Changeset.change(delta_updatable: true)
      |> Repo.update!()

      # and now create some new firmware which can be uploaded to each org
      {:ok, _} =
        NervesHub.Support.Fwup.create_firmware(tmp_dir, "new-firmware", %{
          product: "Same Product Name",
          fwup_version: "1.13.0"
        })

      # sign and upload for org one
      {:ok, new_signed_firmware_one} =
        NervesHub.Support.Fwup.sign_firmware(
          tmp_dir,
          org_key_one.name,
          "new-firmware",
          "new-firmware-signed-one"
        )

      {:ok, new_firmware_one} = Firmwares.create_firmware(org_one, new_signed_firmware_one)

      new_firmware_one
      |> Ecto.Changeset.change(delta_updatable: true)
      |> Repo.update!()

      # sign and upload for org two
      {:ok, new_signed_firmware_two} =
        NervesHub.Support.Fwup.sign_firmware(
          tmp_dir,
          org_key_two.name,
          "new-firmware",
          "new-firmware-signed-two"
        )

      {:ok, new_firmware_two} = Firmwares.create_firmware(org_two, new_signed_firmware_two)

      new_firmware_two
      |> Ecto.Changeset.change(delta_updatable: true)
      |> Repo.update!()

      # create a deployment group for org one with the new firmware
      deployment_group =
        Fixtures.deployment_group_fixture(org_one, new_firmware_one, %{
          name: "Delta deployment updates",
          is_active: true,
          delta_updatable: true
        })
        |> Repo.preload(:firmware)

      # and a device using the old firmware, ready to receive an update
      device =
        Fixtures.device_fixture(org_one, product_one, old_firmware_one, %{
          status: :provisioned,
          deployment_id: deployment_group.id,
          fwup_version: "1.13.0"
        })
        |> Repo.preload(:deployment_group)

      # create a delta firmware for the device
      delta = Fixtures.firmware_delta_fixture(old_firmware_one, new_firmware_one)

      {:ok, delta_url} = Firmwares.get_firmware_url(delta)

      update_payload = Devices.resolve_update(device)

      # confirm that the firmware url is the delta firmware url
      assert delta_url == update_payload.firmware_url
    end
  end

  describe "get_device_firmware_for_delta_generation_by_deployment_group/1" do
    test "returns distinct firmware source and target ids", %{
      org_key: org_key,
      product: product,
      org: org,
      deployment_group: deployment_group,
      firmware: firmware
    } do
      firmware2 = Fixtures.firmware_fixture(org_key, product)
      firmware3 = Fixtures.firmware_fixture(org_key, product)
      firmware4 = Fixtures.firmware_fixture(org_key, product)

      _ =
        Fixtures.device_fixture(org, product, firmware2)
        |> Devices.update_deployment_group(deployment_group)

      _ =
        Fixtures.device_fixture(org, product, firmware2)
        |> Devices.update_deployment_group(deployment_group)

      _ =
        Fixtures.device_fixture(org, product, firmware3)
        |> Devices.update_deployment_group(deployment_group)

      _ =
        Fixtures.device_fixture(org, product, firmware3)
        |> Devices.update_deployment_group(deployment_group)

      _ =
        Fixtures.device_fixture(org, product, firmware4)
        |> Devices.update_deployment_group(deployment_group)

      pairs =
        Devices.get_device_firmware_for_delta_generation_by_deployment_group(deployment_group.id)

      assert length(pairs) == 3
      assert Enum.member?(pairs, {firmware2.id, firmware.id})
      assert Enum.member?(pairs, {firmware3.id, firmware.id})
      assert Enum.member?(pairs, {firmware4.id, firmware.id})
    end
  end

  describe "delta_ready?/2" do
    test "returns false when no matching delta for source is found", %{
      device: device,
      firmware: firmware,
      org_key: org_key,
      product: product
    } do
      firmware2 = Fixtures.firmware_fixture(org_key, product)
      _ = Fixtures.firmware_delta_fixture(firmware2, firmware)

      refute Devices.delta_ready?(device, firmware2)
    end

    test "returns false when no matching delta for target is found", %{
      device: device,
      firmware: firmware,
      org_key: org_key,
      product: product
    } do
      firmware2 = Fixtures.firmware_fixture(org_key, product)
      firmware3 = Fixtures.firmware_fixture(org_key, product)
      _ = Fixtures.firmware_delta_fixture(firmware, firmware2)

      refute Devices.delta_ready?(device, firmware3)
    end

    test "returns false when no matching delta that's completed is found", %{
      device: device,
      firmware: firmware,
      org_key: org_key,
      product: product
    } do
      firmware2 = Fixtures.firmware_fixture(org_key, product)
      _ = Fixtures.firmware_delta_fixture(firmware, firmware2, %{status: :processing})

      refute Devices.delta_ready?(device, firmware2)
    end

    test "returns true when no completed delta is found", %{
      device: device,
      firmware: firmware,
      org_key: org_key,
      product: product
    } do
      firmware2 = Fixtures.firmware_fixture(org_key, product)
      %{status: :completed} = Fixtures.firmware_delta_fixture(firmware, firmware2)

      assert Devices.delta_ready?(device, firmware2)
    end
  end

  describe "get_delta_or_firmware_url/2" do
    test "returns delta url when delta is ready", %{
      device: device,
      deployment_group: deployment_group,
      org_key: org_key,
      product: product
    } do
      target_firmware = Fixtures.firmware_fixture(org_key, product)
      _ = Fixtures.firmware_delta_fixture(deployment_group.firmware, target_firmware)
      device = %{device | firmware_metadata: %{device.firmware_metadata | fwup_version: "1.13.0"}}

      deployment_group = %{
        deployment_group
        | delta_updatable: true,
          firmware: %{target_firmware | delta_updatable: true}
      }

      {:ok, url} = Devices.get_delta_or_firmware_url(device, deployment_group)
      assert String.ends_with?(url, ".delta.fw")
    end

    test "returns firmware url when deployment group and firmware are not delta updatable", %{
      device: device,
      deployment_group: deployment_group,
      firmware: firmware
    } do
      refute deployment_group.delta_updatable
      refute firmware.delta_updatable

      {:ok, url} = Devices.get_delta_or_firmware_url(device, deployment_group)
      assert String.ends_with?(url, "#{firmware.uuid}.fw")
    end

    test "returns firmware url when deployment_group is not delta updatable", %{
      device: device,
      deployment_group: deployment_group,
      firmware: firmware
    } do
      deployment_group = %{
        deployment_group
        | delta_updatable: false,
          firmware: %{firmware | delta_updatable: true}
      }

      {:ok, url} = Devices.get_delta_or_firmware_url(device, deployment_group)
      assert String.ends_with?(url, "#{firmware.uuid}.fw")
    end

    test "returns firmware url when firmware is not delta updatable", %{
      device: device,
      deployment_group: deployment_group,
      firmware: firmware
    } do
      deployment_group = %{
        deployment_group
        | delta_updatable: true,
          firmware: %{firmware | delta_updatable: false}
      }

      {:ok, url} = Devices.get_delta_or_firmware_url(device, deployment_group)
      assert String.ends_with?(url, "#{firmware.uuid}.fw")
    end

    test "returns error if device does not support deltas", %{
      device: device,
      deployment_group: deployment_group,
      org_key: org_key,
      product: product
    } do
      target_firmware = Fixtures.firmware_fixture(org_key, product)
      _ = Fixtures.firmware_delta_fixture(deployment_group.firmware, target_firmware)

      deployment_group = %{
        deployment_group
        | delta_updatable: true,
          firmware: %{target_firmware | delta_updatable: true}
      }

      assert {:error, :device_does_not_support_deltas} = Devices.get_delta_or_firmware_url(device, deployment_group)
    end

    test "returns error if delta isn't ready", %{
      device: device,
      deployment_group: deployment_group,
      org_key: org_key,
      product: product
    } do
      target_firmware = Fixtures.firmware_fixture(org_key, product)
      _ = Fixtures.firmware_delta_fixture(deployment_group.firmware, target_firmware, %{status: :processing})
      device = %{device | firmware_metadata: %{device.firmware_metadata | fwup_version: "1.13.0"}}

      deployment_group = %{
        deployment_group
        | delta_updatable: true,
          firmware: %{target_firmware | delta_updatable: true}
      }

      assert {:error, :waiting_for_delta} = Devices.get_delta_or_firmware_url(device, deployment_group)
    end
  end
end
