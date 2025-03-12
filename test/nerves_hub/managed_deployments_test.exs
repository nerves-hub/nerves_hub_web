defmodule NervesHub.ManagedDeploymentsTest do
  use NervesHub.DataCase, async: false
  use Mimic

  import Phoenix.ChannelTest

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Distributed.Orchestrator, as: DistributedOrchestrator

  alias Ecto.Changeset
  alias Phoenix.Socket.Broadcast

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)

    user2 = Fixtures.user_fixture(%{email: "user2@test.com"})
    org2 = Fixtures.org_fixture(user2, %{name: "org2"})
    product2 = Fixtures.product_fixture(user2, org2)
    org_key2 = Fixtures.org_key_fixture(org2, user2)
    firmware2 = Fixtures.firmware_fixture(org_key2, product2)

    {:ok,
     %{
       org: org,
       org_key: org_key,
       firmware: firmware,
       deployment_group: deployment_group,
       product: product,
       org2: org2,
       org_key2: org_key2,
       firmware2: firmware2,
       product2: product2
     }}
  end

  describe "create deployment" do
    test "create_deployment_group with valid parameters", %{
      org: org,
      firmware: firmware
    } do
      params = %{
        org_id: org.id,
        firmware_id: firmware.id,
        name: "a different name",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false
      }

      {:ok, %ManagedDeployments.DeploymentGroup{} = deployment_group} =
        ManagedDeployments.create_deployment_group(params)

      for key <- Map.keys(params) do
        assert Map.get(deployment_group, key) == Map.get(params, key)
      end
    end

    test "deployments have unique names wrt product", %{
      org: org,
      firmware: firmware,
      deployment_group: existing_deployment_group
    } do
      params = %{
        name: existing_deployment_group.name,
        org_id: org.id,
        firmware_id: firmware.id,
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false
      }

      assert {:error, %Ecto.Changeset{errors: [name: {"has already been taken", _}]}} =
               ManagedDeployments.create_deployment_group(params)
    end

    test "create_deployment_group with invalid parameters" do
      params = %{
        name: "my deployment",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: true
      }

      assert {:error, %Changeset{}} = ManagedDeployments.create_deployment_group(params)
    end
  end

  describe "update_deployment_group" do
    test "updating firmware sends an update message", %{
      org: org,
      org_key: org_key,
      firmware: firmware,
      product: product
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

      Fixtures.firmware_delta_fixture(firmware, new_firmware)

      params = %{
        firmware_id: new_firmware.id,
        org_id: org.id,
        name: "my deployment",
        conditions: %{
          "version" => "< 1.0.1",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false
      }

      {:ok, deployment_group} = ManagedDeployments.create_deployment_group(params)

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment_group.id}")

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true})

      assert_broadcast("deployments/update", %{}, 500)
    end

    test "starts distributed orchestrator if deployment updates to active from inactive and the strategy is to :distributed",
         %{
           deployment_group: deployment_group
         } do
      refute deployment_group.is_active

      :ok =
        Phoenix.PubSub.subscribe(
          NervesHub.PubSub,
          "orchestrator:deployment:#{deployment_group.id}"
        )

      stub(
        DistributedOrchestrator,
        :start_orchestrator,
        fn _deployment_group -> :ok end
      )

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{
          is_active: true,
          orchestrator_strategy: :distributed
        })

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: false})

      topic = "orchestrator:deployment:#{deployment_group.id}"
      assert_receive %Broadcast{topic: ^topic, event: "deactivated"}, 500
    end
  end

  describe "device's matching deployments" do
    test "finds all matching deployments", state do
      %{org: org, product: product, firmware: firmware} = state

      %{id: beta_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          name: "beta",
          conditions: %{"tags" => ["beta"]}
        })

      %{id: rpi_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"]}
        })

      Fixtures.deployment_group_fixture(org, firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi0"]}
      })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [
               %{id: ^beta_deployment_group_id},
               %{id: ^rpi_deployment_group_id}
             ] = ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including the platform", state do
      %{org: org, org_key: org_key, product: product} = state

      rpi_firmware = Fixtures.firmware_fixture(org_key, product, %{platform: "rpi"})
      rpi0_firmware = Fixtures.firmware_fixture(org_key, product, %{platform: "rpi0"})

      %{id: rpi_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, rpi_firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"]}
        })

      Fixtures.deployment_group_fixture(org, rpi0_firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"]}
      })

      device = Fixtures.device_fixture(org, product, rpi_firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^rpi_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including the architecture", state do
      %{org: org, org_key: org_key, product: product} = state

      rpi_firmware = Fixtures.firmware_fixture(org_key, product, %{architecture: "rpi"})
      rpi0_firmware = Fixtures.firmware_fixture(org_key, product, %{architecture: "rpi0"})

      %{id: rpi_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, rpi_firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"]}
        })

      Fixtures.deployment_group_fixture(org, rpi0_firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"]}
      })

      device = Fixtures.device_fixture(org, product, rpi_firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^rpi_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including the version", state do
      %{org: org, product: product, firmware: firmware} = state

      %{id: low_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => "~> 1.0"}
        })

      Fixtures.deployment_group_fixture(org, firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"], "version" => "~> 2.0"}
      })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^low_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including pre versions", state do
      %{org: org, org_key: org_key, product: product, firmware: firmware} = state

      %{id: low_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => "~> 1.0"}
        })

      Fixtures.deployment_group_fixture(org, firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"], "version" => "~> 2.0"}
      })

      firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.2.0-pre"})

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^low_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds the newest firmware version including pre-releases", state do
      %{
        org: org,
        org_key: org_key,
        product: product,
        firmware: %{version: "1.0.0"} = v100_firmware
      } = state

      v090_fw = Fixtures.firmware_fixture(org_key, product, %{version: "0.9.0"})
      v100rc1_fw = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0-rc.1"})
      v100rc2_fw = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0-rc.2"})
      v101_fw = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

      %{id: v100_deployment_id} =
        Fixtures.deployment_group_fixture(org, v100_firmware, %{
          name: v100_firmware.version,
          conditions: %{"version" => "", "tags" => ["next"]}
        })

      %{id: v100rc1_deployment_id} =
        Fixtures.deployment_group_fixture(org, v100rc1_fw, %{
          name: v100rc1_fw.version,
          conditions: %{"version" => "", "tags" => ["next"]}
        })

      %{id: v100rc2_deployment_id} =
        Fixtures.deployment_group_fixture(org, v100rc2_fw, %{
          name: v100rc2_fw.version,
          conditions: %{"version" => "", "tags" => ["next"]}
        })

      %{id: v101_deployment_id} =
        Fixtures.deployment_group_fixture(org, v101_fw, %{
          name: v101_fw.version,
          conditions: %{"version" => "", "tags" => ["next"]}
        })

      device = Fixtures.device_fixture(org, product, v090_fw, %{tags: ["next"]})

      assert [
               %{id: ^v101_deployment_id},
               %{id: ^v100_deployment_id},
               %{id: ^v100rc2_deployment_id},
               %{id: ^v100rc1_deployment_id}
             ] = ManagedDeployments.matching_deployment_groups(device)
    end

    test "ignores device without firmware metadata" do
      assert [] == ManagedDeployments.matching_deployment_groups(%Device{firmware_metadata: nil})

      assert [] ==
               ManagedDeployments.matching_deployment_groups(%Device{firmware_metadata: nil}, [
                 true
               ])

      assert [] ==
               ManagedDeployments.matching_deployment_groups(%Device{firmware_metadata: nil}, [
                 false
               ])
    end
  end

  describe "verify_deployment_group_membership/1" do
    setup %{org: org, product: product, firmware: firmware} = context do
      Map.merge(context, %{
        device: Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})
      })
    end

    test "does nothing when device has no deployment", %{device: device} do
      refute device.deployment_id
      device = ManagedDeployments.verify_deployment_group_membership(device)
      refute device.deployment_id
    end

    test "does nothing when device has deployment and meets matching conditions", %{
      device: device,
      deployment_group: deployment_group
    } do
      device = Devices.update_deployment_group(device, deployment_group)
      assert device.deployment_id

      device = ManagedDeployments.verify_deployment_group_membership(device)
      assert device.deployment_id
    end

    test "removes device from deployment group and creates audit log when platforms don't match",
         %{
           device: device,
           deployment_group: deployment_group
         } do
      {:ok, device} =
        device
        |> Devices.update_deployment_group(deployment_group)
        |> Devices.update_firmware_metadata(%{"platform" => "foobar"})

      device = ManagedDeployments.verify_deployment_group_membership(device)
      refute device.deployment_id

      [audit_log] = AuditLogs.logs_for(deployment_group)
      assert audit_log.description =~ "no longer matches deployment"
    end

    test "removes device from deployment group and creates audit log when architecture doesn't match",
         %{
           device: device,
           deployment_group: deployment_group
         } do
      {:ok, device} =
        device
        |> Devices.update_deployment_group(deployment_group)
        |> Devices.update_firmware_metadata(%{"architecture" => "foobar"})

      device = ManagedDeployments.verify_deployment_group_membership(device)
      refute device.deployment_id

      [audit_log] = AuditLogs.logs_for(deployment_group)
      assert audit_log.description =~ "no longer matches deployment group"
    end

    test "removes device from deployment group and creates audit log when versions don't match",
         %{
           device: device,
           deployment_group: deployment_group
         } do
      {:ok, device} =
        device
        |> Devices.update_deployment_group(deployment_group)
        |> Devices.update_firmware_metadata(%{"version" => "1.0.1"})

      device = ManagedDeployments.verify_deployment_group_membership(device)
      refute device.deployment_id

      [audit_log] = AuditLogs.logs_for(deployment_group)
      assert audit_log.description =~ "no longer matches deployment group"
    end
  end
end
