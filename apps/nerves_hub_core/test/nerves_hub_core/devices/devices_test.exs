defmodule NervesHubCore.DevicesTest do
  use NervesHubCore.DataCase, async: true

  alias NervesHubCore.{Accounts, Fixtures, Devices, Deployments}
  alias NervesHubCore.Devices.DeviceCertificate
  alias Ecto.Changeset

  setup do
    org = Fixtures.org_fixture()
    product = Fixtures.product_fixture(org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment = Fixtures.deployment_fixture(firmware)
    device = Fixtures.device_fixture(org, firmware)
    Fixtures.device_certificate_fixture(device)

    {:ok,
     %{
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
    firmware: firmware
  } do
    params = %{
      org_id: org.id,
      last_known_firmware_id: firmware.id,
      identifier: "valid identifier"
    }

    {:ok, %Devices.Device{} = device} = Devices.create_device(params)

    for key <- Map.keys(params) do
      assert Map.get(device, key) == Map.get(params, key)
    end
  end

  test "org cannot have too many devices" do
    org = Fixtures.org_fixture(%{name: "an org with no devices"})
    product = Fixtures.product_fixture(org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)

    %{devices: org_device_limit} = Accounts.get_org_limit_by_org_id(org.id)

    for i <- 1..org_device_limit do
      params = %{
        org_id: org.id,
        last_known_firmware_id: firmware.id,
        identifier: "id #{i}"
      }

      {:ok, %Devices.Device{}} = Devices.create_device(params)
    end

    params = %{
      org_id: org.id,
      last_known_firmware_id: firmware.id,
      identifier: "too many"
    }

    assert {:error, %Changeset{}} = Devices.create_device(params)
  end

  test "org device count limit can be raised" do
    org = Fixtures.org_fixture(%{name: "an org with no devices"})
    product = Fixtures.product_fixture(org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)

    %{devices: org_device_limit} = Accounts.get_org_limit_by_org_id(org.id)

    for i <- 1..org_device_limit do
      params = %{
        org_id: org.id,
        last_known_firmware_id: firmware.id,
        identifier: "id #{i}"
      }

      {:ok, %Devices.Device{}} = Devices.create_device(params)
    end

    params = %{
      org_id: org.id,
      last_known_firmware_id: firmware.id,
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
    [cert] = Devices.get_device_certificates(device)

    {:ok, _device} = Devices.delete_device(device)

    assert {:error, _} = Devices.get_device_certificate_by_serial(cert.serial)
  end

  test "create_device with invalid parameters", %{firmware: firmware} do
    params = %{
      identifier: "valid identifier",
      architecture: firmware.architecture,
      platform: firmware.platform
    }

    assert {:error, %Changeset{}} = Devices.create_device(params)
  end

  test "cannot create two devices with the same identifier", %{org: org, firmware: firmware} do
    params = %{
      org_id: org.id,
      last_known_firmware_id: firmware.id,
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
      device_id: device_id
    }

    assert {:ok, %DeviceCertificate{device_id: ^device_id}} =
             Devices.create_device_certificate(device, params)
  end

  test "select one device when it has two certificates", %{device: device} do
    now = DateTime.utc_now()

    params = %{
      serial: "12345",
      not_before: now,
      not_after: now,
      device_id: device.id
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
      device_id: device.id
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
      Fixtures.device_fixture(org, firmware, %{
        identifier: "new identifier",
        tags: ["beta", "beta-edge"]
      })

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

    params = %{
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
      device = Fixtures.device_fixture(org, firmware, d_params)
      new_firmware = Fixtures.firmware_fixture(org_key, product, f_params)

      params = %{
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
    org: org,
    org_key: org_key,
    firmware: firmware,
    product: product
  } do
    old_deployment =
      Fixtures.deployment_fixture(firmware, %{
        name: "a different name",
        conditions: %{"tags" => ["beta", "beta-edge"], "version" => ""}
      })

    firmware1 = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0"})

    Deployments.update_deployment(old_deployment, %{firmware_id: firmware1.id, is_active: true})

    device =
      Fixtures.device_fixture(org, firmware, %{
        identifier: "new identifier",
        tags: ["beta", "beta-edge"]
      })

    product2 = Fixtures.product_fixture(org, %{name: "other product"})
    firmware2 = Fixtures.firmware_fixture(org_key, product2)

    params = %{
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
      |> NervesHubCore.Repo.preload(:firmware)

    assert length(deployments) == 1

    for deployment <- deployments do
      assert deployment.firmware.product_id == product.id
    end
  end
end
