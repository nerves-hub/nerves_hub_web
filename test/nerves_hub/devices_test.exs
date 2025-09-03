defmodule NervesHub.DevicesTest do
  use NervesHub.DataCase, async: false

  alias Ecto.Changeset

  alias NervesHub.Accounts
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
       deployment_group: deployment_group,
       device: device,
       device2: device2,
       device3: device3,
       firmware: firmware,
       org: org,
       org_key: org_key,
       product: product,
       user: user
     }}
  end

  test "create_device with valid parameters", %{
    firmware: firmware,
    org: org,
    product: product
  } do
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)

    params = %{
      firmware_metadata: metadata,
      identifier: "valid identifier",
      org_id: org.id,
      product_id: product.id
    }

    {:ok, %Devices.Device{} = device} = Devices.create_device(params)

    for key <- Map.keys(metadata) do
      assert Map.get(device.firmware_metadata, key) == Map.get(metadata, key)
    end
  end

  test "delete_device", %{device: device, org: org} do
    {:ok, _device} = Devices.delete_device(device)

    assert {:error, _} = Devices.get_device_by_org(org, device.id)
  end

  test "destroy_device", %{device: device} do
    {:ok, _} =
      Devices.save_device_health(%{
        "data" => %{},
        "device_id" => device.id,
        "status" => :healthy,
        "status_reasons" => %{}
      })

    {:ok, _device} = Devices.destroy_device(device)

    assert is_nil(Repo.get(Device, device.id))
    refute Repo.exists?(where(DeviceHealth, device_id: ^device.id))
  end

  test "can tag multiple devices", %{
    device: device,
    device2: device2,
    device3: device3,
    user: user
  } do
    devices = [device, device2, device3]
    tags = "New,Tags"

    %{ok: devices} = Devices.tag_devices(devices, user, tags)

    assert Enum.all?(devices, fn device -> device.tags == ["New", "Tags"] end)
  end

  test "can disable updates for multiple devices", %{
    device: device,
    device2: device2,
    device3: device3,
    user: user
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

    {:ok, device} = Devices.update_attempted(device)
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
      architecture: firmware.architecture,
      identifier: "valid identifier",
      platform: firmware.platform
    }

    assert {:error, %Changeset{}} = Devices.create_device(params)
  end

  test "cannot create two devices with the same identifier", %{
    firmware: firmware,
    org: org,
    product: product
  } do
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)

    params = %{
      firmware_metadata: metadata,
      identifier: "valid identifier",
      org_id: org.id,
      product_id: product.id
    }

    assert {:ok, %Devices.Device{}} = Devices.create_device(params)
    assert {:error, %Ecto.Changeset{}} = Devices.create_device(params)
  end

  test "create device certificate", %{cert: cert, device: device} do
    now = DateTime.utc_now()
    device_id = device.id

    params = %{
      aki: "1234",
      der: X509.Certificate.to_der(cert),
      device_id: device_id,
      not_after: now,
      not_before: now,
      serial: "12345",
      ski: "5678"
    }

    assert {:ok, %DeviceCertificate{device_id: ^device_id}} =
             Devices.create_device_certificate(device, params)
  end

  test "create device certificate without subject key id", %{cert: cert, device: device} do
    now = DateTime.utc_now()
    device_id = device.id

    params = %{
      aki: "1234",
      der: X509.Certificate.to_der(cert),
      device_id: device_id,
      not_after: now,
      not_before: now,
      serial: "12345"
    }

    assert {:ok, %DeviceCertificate{device_id: ^device_id}} =
             Devices.create_device_certificate(device, params)
  end

  test "select one device when it has two certificates", %{
    cert: cert,
    db_cert: db_cert,
    device: device
  } do
    now = DateTime.utc_now()

    params = %{
      aki: "1234",
      der: X509.Certificate.to_der(cert),
      not_after: now,
      not_before: now,
      serial: "67890",
      ski: "5678"
    }

    expected_id = device.id

    assert {:ok, %DeviceCertificate{} = db_cert2} =
             Devices.create_device_certificate(device, params)

    assert {:ok, %{id: ^expected_id}} = Devices.get_device_by_certificate(db_cert2)
    assert {:ok, %{id: ^expected_id}} = Devices.get_device_by_certificate(db_cert)
  end

  test "cannot create device certificates with duplicate serial numbers", %{
    cert: cert,
    device: device
  } do
    now = DateTime.utc_now()

    params = %{
      aki: "1234",
      der: X509.Certificate.to_der(cert),
      device_id: device.id,
      not_after: now,
      not_before: now,
      serial: "12345",
      ski: "5678"
    }

    assert {:ok, %DeviceCertificate{}} = Devices.create_device_certificate(device, params)
    assert {:error, %Changeset{}} = Devices.create_device_certificate(device, params)
  end

  test "cannot create device certificates with invalid parameters", %{device: device} do
    params = %{
      device_id: device.id,
      serial: "12345"
    }

    assert {:error, %Changeset{}} = Devices.create_device_certificate(device, params)
  end

  test "create ca certificate with valid params", %{org: org} do
    org_id = org.id

    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)

    {not_before, not_after} = NervesHub.Certificate.get_validity(ca)

    params = %{
      aki: NervesHub.Certificate.get_aki(ca),
      der: X509.Certificate.to_der(ca),
      not_after: not_after,
      not_before: not_before,
      serial: NervesHub.Certificate.get_serial_number(ca),
      ski: NervesHub.Certificate.get_ski(ca)
    }

    assert {:ok, %CACertificate{org_id: ^org_id}} = Devices.create_ca_certificate(org, params)
  end

  test "cannot create ca certificates with duplicate serial numbers", %{org: org} do
    org_id = org.id

    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)

    {not_before, not_after} = NervesHub.Certificate.get_validity(ca)

    params = %{
      aki: NervesHub.Certificate.get_aki(ca),
      der: X509.Certificate.to_der(ca),
      not_after: not_after,
      not_before: not_before,
      serial: NervesHub.Certificate.get_serial_number(ca),
      ski: NervesHub.Certificate.get_ski(ca)
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
      aki: aki,
      der: X509.Certificate.to_der(ca),
      not_after: not_after,
      not_before: not_before,
      serial: serial,
      ski: NervesHub.Certificate.get_ski(ca)
    }

    assert {:ok, %CACertificate{org_id: ^org_id}} = Devices.create_ca_certificate(org, params)
    assert {:ok, %CACertificate{serial: ^serial}} = Devices.get_ca_certificate_by_aki(aki)
  end

  test "get_device_by_identifier with existing device", %{device: target_device, org: org} do
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
      {:ok, device} = Devices.update_attempted(device)
      assert Enum.count(device.update_attempts) == 1

      {:ok, device} = Devices.update_attempted(device)
      assert Enum.count(device.update_attempts) == 2
    end

    test "records and audit log for updating", %{device: device} do
      assert [] = AuditLogs.logs_for(device)

      {:ok, device} = Devices.update_attempted(device)

      [audit_log] = AuditLogs.logs_for(device)

      assert audit_log.description =~ ~r/attempting to update/
    end

    test "resets update attempts on successful update", %{device: device} do
      {:ok, device} = Devices.update_attempted(device)
      assert Enum.count(device.update_attempts) == 1

      {:ok, device} = Devices.firmware_update_successful(device, device.firmware_metadata)
      assert Enum.empty?(device.update_attempts)
    end

    test "clears an inflight update if it matches", %{
      deployment_group: deployment_group,
      device: device
    } do
      {:ok, inflight_update} = Devices.told_to_update(device, deployment_group)

      {:ok, _device} = Devices.firmware_update_successful(device, device.firmware_metadata)

      inflight_update = Repo.reload(inflight_update)
      assert is_nil(inflight_update)
    end

    test "increments the deployment's updated count", %{
      deployment_group: deployment_group,
      device: device
    } do
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

    test "device updates successfully", %{deployment_group: deployment_group, device: device} do
      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      {:ok, device} = Devices.update_attempted(device)

      {:ok, device} = Devices.verify_update_eligibility(device, deployment_group)

      assert device.updates_enabled
      refute device.updates_blocked_until
    end

    test "device updates successfully after a few attempts", %{
      deployment_group: deployment_group,
      device: device
    } do
      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      {:ok, device} = Devices.update_attempted(device)
      {:ok, device} = Devices.update_attempted(device)

      {:ok, device} = Devices.verify_update_eligibility(device, deployment_group)

      assert device.updates_enabled
      refute device.updates_blocked_until
    end

    test "device updates successfully after a few attempts over a long period of time", state do
      %{deployment_group: deployment_group, device: device} = state

      deployment_group = %{
        deployment_group
        | device_failure_rate_amount: 3,
          device_failure_threshold: 6
      }

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      now = DateTime.utc_now()

      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -3600, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -1200, :second))
      {:ok, device} = Devices.update_attempted(device, now)

      {:ok, device} = Devices.verify_update_eligibility(device, deployment_group)

      assert device.updates_enabled
      refute device.updates_blocked_until
    end

    test "device already matches the firmware of the deployment", state do
      %{deployment_group: deployment_group, device: device} = state

      {:error, :up_to_date, _device} = Devices.verify_update_eligibility(device, deployment_group)
    end

    test "device should be rejected for updates based on threshold rate and have it's inflight updates cleared",
         state do
      %{deployment_group: deployment_group, device: device} = state
      deployment_group = %{deployment_group | device_failure_threshold: 6}

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())
      {:ok, _inflight_update} = Devices.told_to_update(device, deployment_group)

      now = DateTime.utc_now()

      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -3600, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -1200, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -500, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -500, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -500, :second))
      {:ok, device} = Devices.update_attempted(device, now)

      {:error, :updates_blocked, device} =
        Devices.verify_update_eligibility(device, deployment_group)

      assert device.updates_blocked_until
      assert device.update_attempts == []
      assert Devices.count_inflight_updates_for(deployment_group) == 0
    end

    test "device should be rejected for updates based on attempt rate and have it's inflight updates cleared",
         state do
      %{deployment_group: deployment_group, device: device} = state

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())
      {:ok, _inflight_update} = Devices.told_to_update(device, deployment_group)

      now = DateTime.utc_now()

      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -13, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -10, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -5, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -2, :second))
      {:ok, device} = Devices.update_attempted(device, now)

      {:error, :updates_blocked, device} =
        Devices.verify_update_eligibility(device, deployment_group)

      assert device.updates_blocked_until
      assert device.update_attempts == []
      assert Devices.count_inflight_updates_for(deployment_group) == 0
    end

    test "device in penalty box should be rejected for updates and have it's inflight updates cleared",
         state do
      %{deployment_group: deployment_group, device: device} = state

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

  describe "inflight updates" do
    test "clears expired inflight updates", %{deployment_group: deployment_group, device: device} do
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
      uuid: uuid,
      version: "1.0.0"
    }

    Devices.update_firmware_metadata(device, firmware_metadata)
  end

  describe "device health reports" do
    test "create new device health", %{device: device} do
      device_health = %{"data" => %{"literally_any_map" => "values"}, "device_id" => device.id}

      assert {:ok, %Devices.DeviceHealth{id: health_id}} =
               Devices.save_device_health(device_health)

      assert %Devices.DeviceHealth{} = Devices.get_latest_health(device.id)

      # Assert device is updated with latest health
      assert %{latest_health_id: ^health_id} = Devices.get_device(device.id)
    end
  end

  describe "update_deployment_group/2" do
    test "updates deployment and broadcasts 'devices/deployment-updated'", %{
      deployment_group: deployment_group,
      device: device
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
      deployment_group: deployment_group,
      device: device
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
            device_id: device.id,
            established_at: DateTime.utc_now() |> DateTime.add(index + 1, :minute),
            last_seen_at: DateTime.utc_now(),
            product_id: product.id,
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
            })
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
          first_seen_at: DateTime.utc_now() |> DateTime.add(-1, :day),
          priority_updates: true
        })

      device3 =
        %{id: device3_id} =
        Fixtures.device_fixture(org, product, deployment_group.firmware, %{
          first_seen_at: DateTime.utc_now() |> DateTime.add(-7, :day),
          priority_updates: true
        })

      device4 =
        %{id: device4_id} =
        Fixtures.device_fixture(org, product, deployment_group.firmware, %{
          first_seen_at: DateTime.utc_now() |> DateTime.add(-3, :day)
        })

      Enum.each([device1, device2, device3, device4], fn device ->
        %{id: latest_connection_id} =
          DeviceConnection.create_changeset(%{
            device_id: device.id,
            established_at: DateTime.utc_now(),
            last_seen_at: DateTime.utc_now(),
            product_id: product.id,
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
            })
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
      product: product,
      tmp_dir: tmp_dir,
      user: user
    } do
      new_org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      old_firmware =
        Fixtures.firmware_fixture(new_org_key, product, %{
          dir: tmp_dir,
          fwup_version: "1.13.0"
        })
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      new_firmware =
        Fixtures.firmware_fixture(new_org_key, product, %{
          dir: tmp_dir,
          fwup_version: "1.13.0"
        })
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      deployment_group =
        Fixtures.deployment_group_fixture(org, new_firmware, %{
          delta_updatable: true,
          is_active: true,
          name: "Delta deployment updates"
        })
        |> Repo.preload(:firmware)

      device =
        Fixtures.device_fixture(org, product, old_firmware, %{
          deployment_id: deployment_group.id,
          fwup_version: "1.13.0",
          status: :provisioned
        })
        |> Repo.preload(:deployment_group)

      delta = Fixtures.firmware_delta_fixture(old_firmware, new_firmware)

      {:ok, delta_url} = Firmwares.get_firmware_url(delta)

      update_payload = Devices.resolve_update(device)

      assert delta_url == update_payload.firmware_url
    end

    test "returns a delta firmware url if it exists for the product the device belongs to", %{
      tmp_dir: tmp_dir,
      user: user
    } do
      # two orgs which the same user belongs to
      {:ok, org_one} = Accounts.create_org(user, %{name: "One-Org"})
      {:ok, org_two} = Accounts.create_org(user, %{name: "Two-Org"})

      org_key_one = Fixtures.org_key_fixture(org_one, user, tmp_dir)
      org_key_two = Fixtures.org_key_fixture(org_two, user, tmp_dir)

      # two products with the same name
      {:ok, product_one} =
        Products.create_product(%{name: "Same Product Name", org_id: org_one.id})

      {:ok, _product_two} =
        Products.create_product(%{name: "Same Product Name", org_id: org_two.id})

      # create some firmware which can be uploaded to each org
      {:ok, _} =
        NervesHub.Support.Fwup.create_firmware(tmp_dir, "old-firmware", %{
          fwup_version: "1.13.0",
          product: "Same Product Name"
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
          fwup_version: "1.13.0",
          product: "Same Product Name"
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
          delta_updatable: true,
          is_active: true,
          name: "Delta deployment updates"
        })
        |> Repo.preload(:firmware)

      # and a device using the old firmware, ready to receive an update
      device =
        Fixtures.device_fixture(org_one, product_one, old_firmware_one, %{
          deployment_id: deployment_group.id,
          fwup_version: "1.13.0",
          status: :provisioned
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
end
