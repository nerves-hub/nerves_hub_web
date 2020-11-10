defmodule NervesHubWebCore.DevicesTest do
  use NervesHubWebCore.DataCase, async: false

  alias NervesHubWebCore.{
    Accounts,
    AuditLogs,
    AuditLogs.AuditLog,
    Fixtures,
    Devices,
    Devices.CACertificate,
    Deployments,
    Firmwares
  }

  alias NervesHubWebCore.Devices.DeviceCertificate
  alias Ecto.Changeset

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment = Fixtures.deployment_fixture(org, firmware)
    device = Fixtures.device_fixture(org, product, firmware)
    Fixtures.device_certificate_fixture(device)

    {:ok,
     %{
       user: user,
       org: org,
       org_key: org_key,
       firmware: firmware,
       device: device,
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

  test "org cannot have too many devices", %{user: user} do
    org = Fixtures.org_fixture(user, %{name: "an_org_with_no_devices"})
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)
    %{devices: org_device_limit} = Accounts.get_org_limit_by_org_id(org.id)

    for i <- 1..org_device_limit do
      params = %{
        org_id: org.id,
        product_id: product.id,
        firmware_metadata: metadata,
        identifier: "id #{i}"
      }

      {:ok, %Devices.Device{}} = Devices.create_device(params)
    end

    params = %{
      org_id: org.id,
      product_id: product.id,
      firmware_metadata: metadata,
      identifier: "too many"
    }

    assert {:error, %Changeset{}} = Devices.create_device(params)
  end

  test "org device count limit can be raised", %{user: user} do
    org = Fixtures.org_fixture(user, %{name: "an_org_with_no_devices"})
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)
    %{devices: org_device_limit} = Accounts.get_org_limit_by_org_id(org.id)

    for i <- 1..org_device_limit do
      params = %{
        org_id: org.id,
        product_id: product.id,
        firmware_metadata: metadata,
        identifier: "id #{i}"
      }

      {:ok, %Devices.Device{}} = Devices.create_device(params)
    end

    params = %{
      org_id: org.id,
      product_id: product.id,
      firmware_metadata: metadata,
      identifier: "more than default"
    }

    Accounts.create_org_limit(%{org_id: org.id, devices: 10})

    assert {:ok, %Devices.Device{}} = Devices.create_device(params)
  end

  test "delete_device", %{
    org: org,
    device: device
  } do
    {:ok, _device} = Devices.delete_device(device)

    assert {:error, _} = Devices.get_device_by_org(org, device.id)
  end

  test "delete_device deletes its certificates", %{
    device: device
  } do
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

  test "create device certificate", %{device: device} do
    now = DateTime.utc_now()
    device_id = device.id

    params = %{
      serial: "12345",
      not_before: now,
      not_after: now,
      device_id: device_id,
      aki: "1234",
      ski: "5678"
    }

    assert {:ok, %DeviceCertificate{device_id: ^device_id}} =
             Devices.create_device_certificate(device, params)
  end

  test "create device certificate without subject key id", %{device: device} do
    now = DateTime.utc_now()
    device_id = device.id

    params = %{
      serial: "12345",
      not_before: now,
      not_after: now,
      device_id: device_id,
      aki: "1234"
    }

    assert {:ok, %DeviceCertificate{device_id: ^device_id}} =
             Devices.create_device_certificate(device, params)
  end

  test "select one device when it has two certificates", %{device: device} do
    now = DateTime.utc_now()

    params = %{
      serial: "67890",
      not_before: now,
      not_after: now,
      aki: "1234",
      ski: "5678"
    }

    assert {:ok, %DeviceCertificate{} = cert1} = Devices.create_device_certificate(device, params)

    assert {:ok, %DeviceCertificate{} = cert2} =
             Devices.create_device_certificate(device, %{params | serial: "56789"})

    assert {:ok, device1} = Devices.get_device_by_certificate(cert1)
    assert {:ok, device2} = Devices.get_device_by_certificate(cert2)
    assert device1.id == device2.id
  end

  test "cannot create device certificates with duplicate serial numbers", %{device: device} do
    now = DateTime.utc_now()

    params = %{
      serial: "12345",
      not_before: now,
      not_after: now,
      device_id: device.id,
      aki: "1234",
      ski: "5678"
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

    {not_before, not_after} = NervesHubWebCore.Certificate.get_validity(ca)

    params = %{
      serial: NervesHubWebCore.Certificate.get_serial_number(ca),
      aki: NervesHubWebCore.Certificate.get_aki(ca),
      ski: NervesHubWebCore.Certificate.get_ski(ca),
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

    {not_before, not_after} = NervesHubWebCore.Certificate.get_validity(ca)

    params = %{
      serial: NervesHubWebCore.Certificate.get_serial_number(ca),
      aki: NervesHubWebCore.Certificate.get_aki(ca),
      ski: NervesHubWebCore.Certificate.get_ski(ca),
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

    {not_before, not_after} = NervesHubWebCore.Certificate.get_validity(ca)

    serial = NervesHubWebCore.Certificate.get_serial_number(ca)
    aki = NervesHubWebCore.Certificate.get_aki(ca)

    params = %{
      serial: serial,
      aki: aki,
      ski: NervesHubWebCore.Certificate.get_ski(ca),
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
      |> NervesHubWebCore.Repo.preload(:firmware)

    assert length(deployments) == 1

    for deployment <- deployments do
      assert deployment.firmware.product_id == product.id
    end
  end

  describe "send_update_message" do
    test "does not send when device needs attention", %{deployment: deployment, device: device} do
      assert Devices.send_update_message(%{device | healthy: false}, deployment) ==
               {:error, :device_unhealthy}
    end

    test "does not send when deployment needs attention", %{
      deployment: deployment,
      device: device
    } do
      assert Devices.send_update_message(device, %{deployment | healthy: false}) ==
               {:error, :deployment_unhealthy}
    end

    test "does not send when firmware_meta is not present", %{
      deployment: deployment,
      device: device
    } do
      assert Devices.send_update_message(%{device | firmware_metadata: nil}, deployment) ==
               {:error, :invalid_firmware_metadata}
    end

    test "does not send when deployment version mismatch", %{
      deployment: deployment,
      device: device
    } do
      conditions = %{deployment.conditions | "version" => "> 1.0.0"}

      assert Devices.send_update_message(device, %{deployment | conditions: conditions}) ==
               {:error, :invalid_deployment_for_device}
    end

    test "does not send when deployment tags mismatch", %{deployment: deployment, device: device} do
      conditions = %{deployment.conditions | "tags" => "wat?!"}

      assert Devices.send_update_message(device, %{deployment | conditions: conditions}) ==
               {:error, :invalid_deployment_for_device}
    end

    test "broadcasts update message", %{
      deployment: deployment,
      device: device,
      firmware: firmware
    } do
      require Phoenix.ChannelTest
      Phoenix.PubSub.subscribe(NervesHubWeb.PubSub, "device:#{device.id}")

      deployment =
        %{deployment | conditions: %{"tags" => device.tags, "version" => "< 2.0.0"}}
        # preload so that we can correctly match
        |> Repo.preload(:firmware)

      Fixtures.firmware_delta_fixture(firmware, deployment.firmware)

      assert {:ok, ^device} = Devices.send_update_message(device, deployment)
      deployment_id = deployment.id

      Phoenix.ChannelTest.assert_broadcast(
        "update",
        %{
          deployment: ^deployment,
          deployment_id: ^deployment_id,
          firmware_url: _,
          firmware_meta: %{}
        }
      )
    end
  end

  describe "resolve_update" do
    test "no update when device needs attention", %{deployment: deployment, device: device} do
      assert Devices.resolve_update(%{device | healthy: false}, deployment) == %{
               update_available: false
             }
    end

    test "no update when deployment needs attention", %{deployment: deployment, device: device} do
      assert Devices.resolve_update(device, %{deployment | healthy: false}) == %{
               update_available: false
             }
    end

    test "no update when firmware_meta is not present", %{deployment: deployment, device: device} do
      assert Devices.resolve_update(%{device | firmware_metadata: nil}, deployment) == %{
               update_available: false
             }
    end

    test "update message when valid", %{
      deployment: deployment,
      device: device,
      firmware: firmware
    } do
      deployment = deployment |> Repo.preload(:firmware)
      Fixtures.firmware_delta_fixture(firmware, deployment.firmware)

      result = Devices.resolve_update(device, deployment)
      {:ok, meta} = Firmwares.metadata_from_firmware(firmware)
      assert result.update_available
      assert result.firmware_url =~ firmware.uuid
      assert result.firmware_meta.uuid == meta.uuid
    end
  end

  test "failure_rate_met?", %{deployment: deployment, device: device} do
    # Build a bunch of failures at quick rate
    Enum.each(1..5, fn i ->
      al = AuditLog.build(deployment, device, :update, %{send_update_message: true})
      time = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> Timex.shift(seconds: i)
      Repo.insert(%{al | inserted_at: time})
    end)

    assert Devices.failure_rate_met?(device, deployment)
  end

  test "failure_threshold_met?", %{deployment: deployment, device: device} do
    # Build a bunch of failures for the device
    Enum.each(1..15, fn i ->
      al = AuditLog.build(deployment, device, :update, %{send_update_message: true})
      time = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> Timex.shift(minutes: i)
      Repo.insert(%{al | inserted_at: time})
    end)

    assert Devices.failure_threshold_met?(device, deployment)
  end

  test "device_connected adds audit log", %{device: device} do
    assert AuditLogs.logs_for(device) == []
    Devices.device_connected(device)
    assert [%AuditLog{description: desc}] = AuditLogs.logs_for(device)
    assert desc =~ "device #{device.identifier} connected to the server"
  end
end
