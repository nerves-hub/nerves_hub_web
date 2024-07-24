defmodule NervesHub.DevicesTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.AuditLogs
  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Repo
  alias Ecto.Changeset

  @valid_fwup_version "1.10.0"

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment = Fixtures.deployment_fixture(org, firmware)
    device = Fixtures.device_fixture(org, product, firmware)
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
       deployment: deployment,
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

  test "get_eligible_deployments returns proper deployments", %{
    org: org,
    org_key: org_key,
    firmware: firmware,
    product: product
  } do
    device =
      Fixtures.device_fixture(org, product, firmware, %{
        identifier: "new identifier",
        tags: ["beta", "beta-edge"]
      })

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})
    Fixtures.firmware_delta_fixture(firmware, new_firmware)

    params = %{
      org_id: org.id,
      firmware_id: new_firmware.id,
      name: "my deployment",
      conditions: %{
        "version" => "< 1.0.1",
        "tags" => ["beta", "beta-edge"]
      },
      is_active: false
    }

    {:ok, deployment} =
      Deployments.create_deployment(params)
      |> elem(1)
      |> Deployments.update_deployment(%{is_active: true})

    {:ok, device_with_firmware} = Devices.get_device_by_org(org, device.id)

    [%Deployments.Deployment{id: dep_id} | _] =
      Devices.get_eligible_deployments(device_with_firmware)

    assert dep_id == deployment.id
  end

  test "get_eligible_deployment does not return incorrect devices", %{
    org: org,
    org_key: org_key,
    firmware: firmware,
    product: product
  } do
    incorrect_params = [
      {%{version: "1.0.0"}, %{identifier: "foo"}},
      {%{}, %{identifier: "foobar", tags: ["beta"]}},
      {%{}, %{identifier: "foobarbaz", architecture: "foo"}},
      {%{}, %{identifier: "foobarbazbang", platform: "foo"}}
    ]

    for {f_params, d_params} <- incorrect_params do
      device = Fixtures.device_fixture(org, product, firmware, d_params)
      new_firmware = Fixtures.firmware_fixture(org_key, product, f_params)

      params = %{
        org_id: org.id,
        firmware_id: new_firmware.id,
        name: "my deployment #{d_params.identifier}",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false
      }

      {:ok, _deployment} =
        Deployments.create_deployment(params)
        |> elem(1)
        |> Deployments.update_deployment(%{is_active: true})

      {:ok, device_with_firmware} = Devices.get_device_by_org(org, device.id)

      assert [] == Devices.get_eligible_deployments(device_with_firmware)
    end
  end

  test "deployments limit deploying by product", %{
    user: user,
    org: org,
    org_key: org_key,
    firmware: firmware,
    product: product
  } do
    old_deployment =
      Fixtures.deployment_fixture(org, firmware, %{
        name: "a different name",
        conditions: %{"tags" => ["beta", "beta-edge"], "version" => ""}
      })

    firmware1 = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0"})

    Deployments.update_deployment(old_deployment, %{firmware_id: firmware1.id, is_active: true})

    device =
      Fixtures.device_fixture(org, product, firmware, %{
        identifier: "new identifier",
        tags: ["beta", "beta-edge"]
      })

    product2 = Fixtures.product_fixture(user, org, %{name: "other product"})
    firmware2 = Fixtures.firmware_fixture(org_key, product2)

    params = %{
      org_id: org.id,
      firmware_id: firmware2.id,
      name: "my deployment",
      conditions: %{
        "version" => "",
        "tags" => ["beta", "beta-edge"]
      },
      is_active: false
    }

    {:ok, _deployment2} =
      Deployments.create_deployment(params)
      |> elem(1)
      |> Deployments.update_deployment(%{is_active: true})

    {:ok, device_with_firmware} = Devices.get_device_by_org(org, device.id)

    deployments =
      Devices.get_eligible_deployments(device_with_firmware)
      |> NervesHub.Repo.preload(:firmware)

    assert length(deployments) == 1

    for deployment <- deployments do
      assert deployment.firmware.product_id == product.id
    end
  end

  test "delta_updatable?", %{
    firmware: source,
    product: product,
    deployment: deployment
  } do
    fwup_version = @valid_fwup_version
    %{firmware: target} = Repo.preload(deployment, :firmware)

    assert Devices.delta_updatable?(source, target, product, fwup_version) == false

    source = Ecto.Changeset.change(source, delta_updatable: true) |> Repo.update!()
    target = Ecto.Changeset.change(target, delta_updatable: true) |> Repo.update!()

    assert product.delta_updatable == true
    assert source.delta_updatable == true
    assert target.delta_updatable == true

    assert Devices.delta_updatable?(source, target, product, fwup_version) == true

    # case where the source firmware does not exist
    assert Devices.delta_updatable?(nil, target, product, fwup_version) == false
  end

  test "matches_deployment? works when device and/or deployment tags are nil", %{
    deployment: deployment,
    device: device
  } do
    # There is a verion check before the tags, so load both versions
    # here to ensure they match and we get to the tag check
    device = put_in(device.firmware_metadata.version, "1.0.0")
    deployment = put_in(deployment.conditions["version"], "1.0.0")

    nil_tags_deployment = put_in(deployment.conditions["tags"], nil)

    refute Devices.matches_deployment?(%{device | tags: nil}, deployment)
    assert Devices.matches_deployment?(%{device | tags: nil}, nil_tags_deployment)
    assert Devices.matches_deployment?(device, nil_tags_deployment)
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

      {:ok, device} = Devices.firmware_update_successful(device)
      assert Enum.empty?(device.update_attempts)
    end

    test "clears an inflight update if it matches", %{device: device, deployment: deployment} do
      deployment = Repo.preload(deployment, [:firmware])
      {:ok, inflight_update} = Devices.told_to_update(device, deployment)

      {:ok, _device} = Devices.firmware_update_successful(device)

      inflight_update = Repo.reload(inflight_update)
      assert is_nil(inflight_update)
    end

    test "increments the deployment's updated count", %{device: device, deployment: deployment} do
      deployment = Repo.preload(deployment, [:firmware])
      assert deployment.current_updated_devices == 0

      {:ok, _inflight_update} = Devices.told_to_update(device, deployment)

      {:ok, _device} = Devices.firmware_update_successful(device)

      deployment = Repo.reload(deployment)
      assert deployment.current_updated_devices == 1
    end

    test "device updates successfully", %{device: device, deployment: deployment} do
      deployment = Repo.preload(deployment, [:firmware])

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      {:ok, device} = Devices.update_attempted(device)

      {:ok, device} = Devices.verify_update_eligibility(device, deployment)

      assert device.updates_enabled
      refute device.updates_blocked_until
    end

    test "device updates successfully after a few attempts", %{
      device: device,
      deployment: deployment
    } do
      deployment = Repo.preload(deployment, [:firmware])

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      {:ok, device} = Devices.update_attempted(device)
      {:ok, device} = Devices.update_attempted(device)

      {:ok, device} = Devices.verify_update_eligibility(device, deployment)

      assert device.updates_enabled
      refute device.updates_blocked_until
    end

    test "device updates successfully after a few attempts over a long period of time", state do
      %{device: device, deployment: deployment} = state
      deployment = %{deployment | device_failure_threshold: 6, device_failure_rate_amount: 3}
      deployment = Repo.preload(deployment, [:firmware])

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      now = DateTime.utc_now()

      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -3600, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -1200, :second))
      {:ok, device} = Devices.update_attempted(device, now)

      {:ok, device} = Devices.verify_update_eligibility(device, deployment)

      assert device.updates_enabled
      refute device.updates_blocked_until
    end

    test "device already matches the firmware of the deployment", state do
      %{device: device, deployment: deployment} = state
      deployment = Repo.preload(deployment, [:firmware])

      {:error, :up_to_date, _device} = Devices.verify_update_eligibility(device, deployment)
    end

    test "device is unhealthy and should be put in the penalty box based on total attemps",
         state do
      %{device: device, deployment: deployment} = state
      deployment = Repo.preload(deployment, [:firmware])
      deployment = %{deployment | device_failure_threshold: 6}

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      now = DateTime.utc_now()

      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -3600, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -1200, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -500, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -500, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -500, :second))
      {:ok, device} = Devices.update_attempted(device, now)

      {:error, :updates_blocked, device} = Devices.verify_update_eligibility(device, deployment)

      assert device.updates_blocked_until
    end

    test "device is unhealthy and should be put in the penalty box based on attempt rate",
         state do
      %{device: device, deployment: deployment} = state
      deployment = Repo.preload(deployment, [:firmware])

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      now = DateTime.utc_now()

      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -13, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -10, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -5, :second))
      {:ok, device} = Devices.update_attempted(device, DateTime.add(now, -2, :second))
      {:ok, device} = Devices.update_attempted(device, now)

      {:error, :updates_blocked, device} = Devices.verify_update_eligibility(device, deployment)

      assert device.updates_blocked_until
    end

    test "device is in the penalty box and should be rejected for updates", state do
      %{device: device, deployment: deployment} = state
      deployment = Repo.preload(deployment, [:firmware])

      {:ok, device} = update_firmware_uuid(device, Ecto.UUID.generate())

      now = DateTime.utc_now()

      # future time
      device = %{device | updates_blocked_until: DateTime.add(now, 1, :second)}

      {:error, :updates_blocked, _device} =
        Devices.verify_update_eligibility(device, deployment, now)

      # now
      device = %{device | updates_blocked_until: now}
      {:ok, _device} = Devices.verify_update_eligibility(device, deployment, now)

      # past time
      device = %{device | updates_blocked_until: DateTime.add(now, -1, :second)}
      {:ok, _device} = Devices.verify_update_eligibility(device, deployment, now)
    end
  end

  describe "update device" do
    test "success: deployment is not changed if tags don't change" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user, %{name: "org"})
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      deployment =
        Fixtures.deployment_fixture(org, firmware, %{conditions: %{"tags" => ["beta"]}})

      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})
      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

      device = Deployments.set_deployment(device)
      assert device.deployment_id == deployment.id

      {:ok, device} = Devices.update_device(device, %{description: "Updated description"})
      assert device.deployment_id == deployment.id
    end

    test "success: deployment changes if the tags change" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user, %{name: "org"})
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      deployment_one =
        Fixtures.deployment_fixture(org, firmware, %{
          name: "alpha",
          conditions: %{"tags" => ["alpha"]}
        })

      {:ok, deployment_one} = Deployments.update_deployment(deployment_one, %{is_active: true})

      deployment_two =
        Fixtures.deployment_fixture(org, firmware, %{
          name: "beta",
          conditions: %{"tags" => ["beta"]}
        })

      {:ok, deployment_two} = Deployments.update_deployment(deployment_two, %{is_active: true})
      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["alpha"]})

      device = Deployments.set_deployment(device)
      assert device.deployment_id == deployment_one.id

      {:ok, device} = Devices.update_device(device, %{tags: ["beta"]})
      assert device.deployment_id == deployment_two.id
    end
  end

  describe "firmware status" do
    test "latest: no deployment" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user, %{name: "org"})
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["alpha"]})

      refute device.deployment_id
      assert Devices.firmware_status(device) == "latest"
    end

    test "latest: firmware matches the deployment" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user, %{name: "org"})
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      deployment =
        Fixtures.deployment_fixture(org, firmware, %{
          name: "alpha",
          conditions: %{"tags" => ["alpha"]}
        })

      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["alpha"]})
      device = Deployments.set_deployment(device)

      assert device.deployment_id == deployment.id
      assert device.updates_enabled

      assert Devices.firmware_status(device) == "latest"
    end

    test "updating: there are update attempts" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user, %{name: "org"})
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware_one = Fixtures.firmware_fixture(org_key, product)
      firmware_two = Fixtures.firmware_fixture(org_key, product)

      deployment =
        Fixtures.deployment_fixture(org, firmware_one, %{
          name: "alpha",
          conditions: %{"tags" => ["alpha"]}
        })

      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})

      device = Fixtures.device_fixture(org, product, firmware_two, %{tags: ["alpha"]})
      device = Deployments.set_deployment(device)
      {:ok, device} = Devices.update_attempted(device)

      assert device.deployment_id == deployment.id
      assert device.updates_enabled

      assert Devices.firmware_status(device) == "updating"
    end

    test "pending: updates are disabled" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user, %{name: "org"})
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware_one = Fixtures.firmware_fixture(org_key, product)
      firmware_two = Fixtures.firmware_fixture(org_key, product)

      deployment =
        Fixtures.deployment_fixture(org, firmware_one, %{
          name: "alpha",
          conditions: %{"tags" => ["alpha"]}
        })

      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})

      device = Fixtures.device_fixture(org, product, firmware_two, %{tags: ["alpha"]})
      device = Deployments.set_deployment(device)
      {:ok, device} = Devices.disable_updates(device, user)

      assert device.deployment_id == deployment.id
      refute device.updates_enabled

      assert Devices.firmware_status(device) == "pending"
    end

    test "pending: still waiting on updating" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user, %{name: "org"})
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware_one = Fixtures.firmware_fixture(org_key, product)
      firmware_two = Fixtures.firmware_fixture(org_key, product)

      deployment =
        Fixtures.deployment_fixture(org, firmware_one, %{
          name: "alpha",
          conditions: %{"tags" => ["alpha"]}
        })

      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})

      device = Fixtures.device_fixture(org, product, firmware_two, %{tags: ["alpha"]})
      device = Deployments.set_deployment(device)

      assert device.deployment_id == deployment.id
      assert device.updates_enabled

      assert Devices.firmware_status(device) == "pending"
    end
  end

  describe "inflight updates" do
    test "clears expired inflight updates", %{device: device, deployment: deployment} do
      deployment = Repo.preload(deployment, :firmware)
      Fixtures.inflight_update(device, deployment)
      assert {0, _} = Devices.delete_expired_inflight_updates()

      Devices.clear_inflight_update(device)

      expires_at =
        DateTime.utc_now()
        |> DateTime.shift(hour: -1)
        |> DateTime.truncate(:second)

      Fixtures.inflight_update(device, deployment, %{"expires_at" => expires_at})
      assert {1, _} = Devices.delete_expired_inflight_updates()
    end
  end

  describe "updates connection details" do
    test "marks a device as connected", %{org: org, product: product, firmware: firmware} do
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, updated} = Devices.device_connected(device)

      assert updated.connection_status == :connected
      assert recent_datetime(updated.connection_established_at)
      assert recent_datetime(updated.connection_last_seen_at)
      assert updated.connection_disconnected_at == nil
    end

    test "marks a device as disconnected", %{org: org, product: product, firmware: firmware} do
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, updated} = Devices.device_connected(device)
      {:ok, again} = Devices.device_disconnected(updated)

      assert again.connection_status == :disconnected
      assert recent_datetime(again.connection_established_at)
      assert recent_datetime(again.connection_last_seen_at)
      assert recent_datetime(again.connection_disconnected_at)
    end

    test "marks a devices last seen information", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, updated} = Devices.device_heartbeat(device)

      assert updated.connection_status == :connected
      assert recent_datetime(updated.connection_last_seen_at)
      assert updated.connection_disconnected_at == nil
    end
  end

  defp recent_datetime(datetime) do
    DateTime.diff(DateTime.utc_now(), datetime, :second) <= 5
  end

  describe "clean up device connection statuses" do
    test "don't change the connection status of devices with a recent heartbeat", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      Fixtures.device_fixture(org, product, firmware, %{
        connection_status: :connected,
        connection_established_at: DateTime.shift(DateTime.utc_now(), minute: -10),
        connection_last_seen_at: DateTime.shift(DateTime.utc_now(), minute: -1)
      })

      Fixtures.device_fixture(org, product, firmware, %{
        connection_status: :connected,
        connection_established_at: DateTime.shift(DateTime.utc_now(), minute: -9),
        connection_last_seen_at: DateTime.shift(DateTime.utc_now(), minute: -2)
      })

      Fixtures.device_fixture(org, product, firmware, %{
        connection_status: :connected,
        connection_established_at: DateTime.shift(DateTime.utc_now(), minute: -11),
        connection_last_seen_at: DateTime.shift(DateTime.utc_now(), minute: -1)
      })

      assert Devices.connected_count(product) == 3
      Devices.clean_connection_states()
      assert Devices.connected_count(product) == 3
    end

    test "clean connection status of devices not seen recently", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      Fixtures.device_fixture(org, product, firmware, %{
        connection_status: :connected,
        connection_established_at: DateTime.shift(DateTime.utc_now(), minute: -10),
        connection_last_seen_at: DateTime.shift(DateTime.utc_now(), minute: -1)
      })

      Fixtures.device_fixture(org, product, firmware, %{
        connection_status: :connected,
        connection_established_at: DateTime.shift(DateTime.utc_now(), minute: -25),
        connection_last_seen_at: DateTime.shift(DateTime.utc_now(), minute: -15)
      })

      Fixtures.device_fixture(org, product, firmware, %{
        connection_status: :connected,
        connection_established_at: DateTime.shift(DateTime.utc_now(), minute: -47),
        connection_last_seen_at: DateTime.shift(DateTime.utc_now(), minute: -9)
      })

      assert Devices.connected_count(product) == 3
      Devices.clean_connection_states()
      assert Devices.connected_count(product) == 1
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

    Devices.update_firmware_metadata(device, firmware_metadata)
  end

  describe "device health reports" do
    test "create new device health", %{device: device} do
      device_health = %{"device_id" => device.id, "data" => %{"literally_any_map" => "values"}}
      assert {:ok, %Devices.DeviceHealth{}} = Devices.save_device_health(device_health)
      assert %Devices.DeviceHealth{} = Devices.get_latest_health(device.id)
    end

    test "create health reports over limit and then clean down to default limit", %{
      device: device
    } do
      device_health = %{"device_id" => device.id, "data" => %{"literally_any_map" => "values"}}

      for x <- 0..9 do
        days_ago = DateTime.shift(DateTime.utc_now(), day: -x)

        inserted =
          device_health
          |> Devices.DeviceHealth.save()
          |> Ecto.Changeset.put_change(:inserted_at, days_ago)
          |> Repo.insert()

        assert {:ok, %Devices.DeviceHealth{}} = inserted
      end

      healths = Devices.get_all_health(device.id)
      assert 10 = Enum.count(healths)

      Devices.truncate_device_health()

      healths = Devices.get_all_health(device.id)
      assert 7 = Enum.count(healths)
    end
  end
end
