defmodule NervesHub.ManagedDeploymentsTest do
  use NervesHub.DataCase, async: false
  use Mimic

  import Phoenix.ChannelTest

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.Distributed.Orchestrator, as: DistributedOrchestrator
  alias NervesHub.Workers.FirmwareDeltaBuilder

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
       deployment_group: deployment_group,
       firmware: firmware,
       firmware2: firmware2,
       org: org,
       org2: org2,
       org_key: org_key,
       org_key2: org_key2,
       product: product,
       product2: product2
     }}
  end

  describe "create deployment" do
    test "create_deployment_group with valid parameters", %{
      firmware: firmware,
      org: org
    } do
      params = %{
        conditions: %{
          "tags" => ["beta", "beta-edge"],
          "version" => "< 1.0.0"
        },
        firmware_id: firmware.id,
        is_active: false,
        name: "a different name",
        org_id: org.id,
        product_id: firmware.product_id
      }

      {:ok, %DeploymentGroup{} = deployment_group} =
        ManagedDeployments.create_deployment_group(params)

      for key <- Map.keys(params) do
        assert Map.get(deployment_group, key) == Map.get(params, key)
      end
    end

    test "deployments have unique names wrt product", %{
      deployment_group: existing_deployment_group,
      firmware: firmware,
      org: org
    } do
      params = %{
        conditions: %{
          "tags" => ["beta", "beta-edge"],
          "version" => "< 1.0.0"
        },
        firmware_id: firmware.id,
        is_active: false,
        name: existing_deployment_group.name,
        org_id: org.id,
        product_id: firmware.product_id
      }

      assert {:error, %Ecto.Changeset{errors: [name: {"has already been taken", _}]}} =
               ManagedDeployments.create_deployment_group(params)
    end

    test "create_deployment_group with invalid parameters" do
      params = %{
        conditions: %{
          "tags" => ["beta", "beta-edge"],
          "version" => "< 1.0.0"
        },
        is_active: true,
        name: "my deployment"
      }

      assert {:error, %Changeset{}} = ManagedDeployments.create_deployment_group(params)
    end
  end

  describe "update_deployment_group" do
    test "updating firmware sends an update message", %{
      firmware: firmware,
      org: org,
      org_key: org_key,
      product: product
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

      Fixtures.firmware_delta_fixture(firmware, new_firmware)

      params = %{
        conditions: %{
          "tags" => ["beta", "beta-edge"],
          "version" => "< 1.0.1"
        },
        firmware_id: new_firmware.id,
        is_active: false,
        name: "my deployment",
        org_id: org.id,
        product_id: new_firmware.product_id
      }

      {:ok, deployment_group} = ManagedDeployments.create_deployment_group(params)

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment_group.id}")

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true})

      assert_broadcast("deployments/update", %{}, 500)
    end

    test "starts distributed orchestrator if deployment updates to active from inactive",
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
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true})

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: false})

      topic = "orchestrator:deployment:#{deployment_group.id}"
      assert_receive %Broadcast{event: "deactivated", topic: ^topic}, 500
    end

    test "triggers delta generation when firmware is updated and delta updates are enabled",
         %{
           deployment_group: deployment_group,
           firmware: %{id: firmware_id} = firmware,
           firmware2: %{id: firmware2_id} = firmware2,
           org: org,
           product: product
         } do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: true})

      assert deployment_group.delta_updatable
      assert deployment_group.firmware_id == firmware.id

      device =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})
        |> Devices.update_deployment_group(deployment_group)

      assert device.deployment_id == deployment_group.id

      expect(
        FirmwareDeltaBuilder,
        :start,
        fn ^firmware_id, ^firmware2_id -> :ok end
      )

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: firmware2.id})
    end

    test "triggers delta generation when delta updates are enabled",
         %{
           deployment_group: deployment_group,
           firmware: %{id: firmware_id} = firmware,
           firmware2: %{id: firmware2_id} = firmware2,
           org: org,
           product: product
         } do
      refute deployment_group.delta_updatable
      assert deployment_group.firmware_id == firmware.id

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: firmware2.id})

      device =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})
        |> Devices.update_deployment_group(deployment_group)

      assert device.deployment_id == deployment_group.id

      expect(
        FirmwareDeltaBuilder,
        :start,
        fn ^firmware_id, ^firmware2_id -> :ok end
      )

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: true})
    end

    test "does not trigger delta generation if firmware has not changed",
         %{
           deployment_group: deployment_group,
           firmware: firmware,
           org: org,
           product: product
         } do
      refute deployment_group.delta_updatable
      assert deployment_group.firmware_id == firmware.id

      device =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})
        |> Devices.update_deployment_group(deployment_group)

      assert device.deployment_id == deployment_group.id

      reject(FirmwareDeltaBuilder, :start, 2)

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: true})
    end
  end

  describe "devices matching deployments" do
    test "finds all matching deployments", state do
      %{firmware: firmware, org: org, product: product} = state

      %{id: beta_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          conditions: %{"tags" => ["beta"], "version" => ""},
          name: "beta"
        })

      %{id: rpi_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          conditions: %{"tags" => ["rpi"], "version" => ""},
          name: "rpi"
        })

      Fixtures.deployment_group_fixture(org, firmware, %{
        conditions: %{"tags" => ["rpi0"], "version" => ""},
        name: "rpi0"
      })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [
               %{id: ^beta_deployment_group_id},
               %{id: ^rpi_deployment_group_id}
             ] = ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployment with no tag condition", state do
      %{firmware: firmware, org: org, product: product} = state

      %{id: blank_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          conditions: %{"tags" => [], "version" => ""},
          name: "beta"
        })

      Fixtures.deployment_group_fixture(org, firmware, %{
        conditions: %{"tags" => ["rpi"], "version" => ""},
        name: "rpi"
      })

      Fixtures.deployment_group_fixture(org, firmware, %{
        conditions: %{"tags" => ["rpi0"], "version" => ""},
        name: "rpi0"
      })

      %{tags: []} = device = Fixtures.device_fixture(org, product, firmware, %{tags: []})

      assert [
               %{id: ^blank_deployment_group_id}
             ] = ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployment when device tags is null", state do
      %{firmware: firmware, org: org, product: product} = state

      %{id: blank_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          conditions: %{"tags" => [], "version" => ""},
          name: "beta"
        })

      Fixtures.deployment_group_fixture(org, firmware, %{
        conditions: %{"tags" => ["rpi"], "version" => ""},
        name: "rpi"
      })

      Fixtures.deployment_group_fixture(org, firmware, %{
        conditions: %{"tags" => ["rpi0"], "version" => ""},
        name: "rpi0"
      })

      %{tags: nil} = device = Fixtures.device_fixture(org, product, firmware, %{tags: nil})

      assert [
               %{id: ^blank_deployment_group_id}
             ] = ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including the platform", state do
      %{org: org, org_key: org_key, product: product} = state

      rpi_firmware = Fixtures.firmware_fixture(org_key, product, %{platform: "rpi"})
      rpi0_firmware = Fixtures.firmware_fixture(org_key, product, %{platform: "rpi0"})

      %{id: rpi_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, rpi_firmware, %{
          conditions: %{"tags" => ["rpi"], "version" => ""},
          name: "rpi"
        })

      Fixtures.deployment_group_fixture(org, rpi0_firmware, %{
        conditions: %{"tags" => ["rpi"], "version" => ""},
        name: "rpi0"
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
          conditions: %{"tags" => ["rpi"], "version" => ""},
          name: "rpi"
        })

      Fixtures.deployment_group_fixture(org, rpi0_firmware, %{
        conditions: %{"tags" => ["rpi"], "version" => ""},
        name: "rpi0"
      })

      device = Fixtures.device_fixture(org, product, rpi_firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^rpi_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including the version", state do
      %{firmware: firmware, org: org, product: product} = state

      %{id: low_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          conditions: %{"tags" => ["rpi"], "version" => "~> 1.0"},
          name: "rpi"
        })

      Fixtures.deployment_group_fixture(org, firmware, %{
        conditions: %{"tags" => ["rpi"], "version" => "~> 2.0"},
        name: "rpi0"
      })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^low_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including pre versions", state do
      %{firmware: firmware, org: org, org_key: org_key, product: product} = state

      %{id: low_deployment_group_id} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          conditions: %{"tags" => ["rpi"], "version" => "~> 1.0"},
          name: "rpi"
        })

      Fixtures.deployment_group_fixture(org, firmware, %{
        conditions: %{"tags" => ["rpi"], "version" => "~> 2.0"},
        name: "rpi0"
      })

      firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.2.0-pre"})

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^low_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds the newest firmware version including pre-releases", state do
      %{
        firmware: %{version: "1.0.0"} = v100_firmware,
        org: org,
        org_key: org_key,
        product: product
      } = state

      v090_fw = Fixtures.firmware_fixture(org_key, product, %{version: "0.9.0"})
      v100rc1_fw = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0-rc.1"})
      v100rc2_fw = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0-rc.2"})
      v101_fw = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

      %{id: v100_deployment_id} =
        Fixtures.deployment_group_fixture(org, v100_firmware, %{
          conditions: %{"tags" => ["next"], "version" => ""},
          name: v100_firmware.version
        })

      %{id: v100rc1_deployment_id} =
        Fixtures.deployment_group_fixture(org, v100rc1_fw, %{
          conditions: %{"tags" => ["next"], "version" => ""},
          name: v100rc1_fw.version
        })

      %{id: v100rc2_deployment_id} =
        Fixtures.deployment_group_fixture(org, v100rc2_fw, %{
          conditions: %{"tags" => ["next"], "version" => ""},
          name: v100rc2_fw.version
        })

      %{id: v101_deployment_id} =
        Fixtures.deployment_group_fixture(org, v101_fw, %{
          conditions: %{"tags" => ["next"], "version" => ""},
          name: v101_fw.version
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
    setup %{firmware: firmware, org: org, product: product} = context do
      Map.put(context, :device, Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]}))
    end

    test "does nothing when device has no deployment", %{device: device} do
      refute device.deployment_id
      device = ManagedDeployments.verify_deployment_group_membership(device)
      refute device.deployment_id
    end

    test "does nothing when device has deployment and meets matching conditions", %{
      deployment_group: deployment_group,
      device: device
    } do
      device = Devices.update_deployment_group(device, deployment_group)
      assert device.deployment_id

      device = ManagedDeployments.verify_deployment_group_membership(device)
      assert device.deployment_id
    end

    test "removes device from deployment group and creates audit log when platforms don't match",
         %{
           deployment_group: deployment_group,
           device: device
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
           deployment_group: deployment_group,
           device: device
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
           deployment_group: deployment_group,
           device: device
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

    test "removes device from deployment group and creates audit log when deployment group version constraint is invalid",
         %{
           deployment_group: deployment_group,
           device: device
         } do
      {:ok, _} =
        deployment_group
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:conditions, %{"tags" => ["beta", "rpi"], "version" => "0.1"})
        |> Repo.update()

      deployment_group = Repo.reload(deployment_group)

      device = Devices.update_deployment_group(device, deployment_group)

      device = ManagedDeployments.verify_deployment_group_membership(device)
      refute device.deployment_id

      [audit_log] = AuditLogs.logs_for(deployment_group)
      assert audit_log.description =~ "no longer matches deployment group"
    end
  end

  describe "matched_devices_count/2" do
    setup %{firmware: firmware, org: org, product: product} =
            context do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(%{
          conditions: %{
            "tags" => [],
            "version" => "> 1.0.0"
          },
          firmware_id: firmware.id,
          is_active: false,
          name: "Deployment 123",
          org_id: org.id,
          product_id: firmware.product_id
        })

      Fixtures.device_fixture(org, product, firmware, %{
        deployment_id: deployment_group.id,
        tags: ["foo"]
      })

      Fixtures.device_fixture(org, product, firmware, %{
        deployment_id: deployment_group.id,
        tags: ["beta", "rpi"]
      })

      Fixtures.device_fixture(org, product, %{firmware | version: "1.2.0"}, %{
        deployment_id: deployment_group.id,
        tags: ["beta", "rpi"]
      })

      Map.put(context, :deployment_group, deployment_group)
    end

    test "count for deployment group with version but no tags", %{
      deployment_group: deployment_group
    } do
      assert ManagedDeployments.matched_devices_count(deployment_group, in_deployment: true) == 1
    end

    test "counts devices for deployment group with tags but no version", %{
      deployment_group: deployment_group
    } do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{
          conditions: %{"tags" => ["beta", "rpi"], "version" => ""}
        })

      assert ManagedDeployments.matched_devices_count(deployment_group, in_deployment: true) == 2
    end

    test "counts devices for deployment group with tags and version", %{
      deployment_group: deployment_group
    } do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{
          conditions: %{"tags" => ["beta", "rpi"], "version" => "> 1.1.0"}
        })

      assert ManagedDeployments.matched_devices_count(deployment_group, in_deployment: true) == 1
    end

    test "accounts for devices outside of deployment group", %{
      deployment_group: deployment_group,
      firmware: firmware,
      org: org,
      product: product
    } do
      device =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta", "rpi"]
        })

      refute device.deployment_id

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{
          conditions: %{"tags" => ["beta", "rpi"], "version" => ""}
        })

      assert ManagedDeployments.matched_devices_count(deployment_group, in_deployment: false) == 1
    end

    test "devices outside deployment group account for platform and architecture", %{
      deployment_group: deployment_group,
      firmware: firmware,
      org: org,
      product: product
    } do
      device =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta", "rpi"]
        })

      refute device.deployment_id

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{
          conditions: %{"tags" => ["beta", "rpi"], "version" => ""}
        })

      assert ManagedDeployments.matched_devices_count(deployment_group, in_deployment: false) == 1
    end
  end

  describe "matched_device_ids/2" do
    test "takes platform and architecture into account", %{
      firmware: firmware,
      org: org,
      product: product
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(%{
          conditions: %{
            "tags" => ["beta", "rpi"],
            "version" => "1.0.0"
          },
          firmware_id: firmware.id,
          is_active: false,
          name: "Deployment 123",
          org_id: org.id,
          product_id: firmware.product_id
        })

      _device1 =
        Fixtures.device_fixture(
          org,
          product,
          %{firmware | architecture: "bar", platform: "foo"},
          %{
            tags: ["beta", "rpi"]
          }
        )

      device2 =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta", "rpi"]
        })

      assert ManagedDeployments.matched_device_ids(deployment_group, in_deployment: false) == [
               device2.id
             ]
    end

    test "matches against tags and version", %{
      firmware: firmware,
      org: org,
      product: product
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(%{
          conditions: %{
            "tags" => ["beta", "rpi"],
            "version" => "1.0.0"
          },
          firmware_id: firmware.id,
          is_active: false,
          name: "Deployment 123",
          org_id: org.id,
          product_id: firmware.product_id
        })

      _device1 =
        Fixtures.device_fixture(
          org,
          product,
          firmware,
          %{
            tags: ["foo"]
          }
        )

      _device2 =
        Fixtures.device_fixture(org, product, %{firmware | version: "3.0.0"}, %{
          tags: ["beta", "rpi"]
        })

      device3 =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta", "rpi"]
        })

      assert ManagedDeployments.matched_device_ids(deployment_group, in_deployment: false) == [
               device3.id
             ]
    end

    test "matches against only tags if deployment group has no version", %{
      firmware: firmware,
      org: org,
      product: product
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(%{
          conditions: %{
            "tags" => ["beta", "rpi"],
            "version" => ""
          },
          firmware_id: firmware.id,
          is_active: false,
          name: "Deployment 123",
          org_id: org.id,
          product_id: firmware.product_id
        })

      device1 =
        Fixtures.device_fixture(
          org,
          product,
          firmware,
          %{
            tags: ["beta", "rpi", "foo"]
          }
        )

      device2 =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta", "rpi"]
        })

      device_ids = ManagedDeployments.matched_device_ids(deployment_group, in_deployment: false)

      assert Enum.member?(device_ids, device1.id)
      assert Enum.member?(device_ids, device2.id)
    end

    test "matches against only version if deployment group has no tags", %{
      firmware: firmware,
      org: org,
      product: product
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(%{
          conditions: %{
            "tags" => [],
            "version" => "< 1.0.0"
          },
          firmware_id: firmware.id,
          is_active: false,
          name: "Deployment 123",
          org_id: org.id,
          product_id: firmware.product_id
        })

      _device1 =
        Fixtures.device_fixture(
          org,
          product,
          firmware,
          %{
            tags: ["beta", "rpi"]
          }
        )

      device2 =
        Fixtures.device_fixture(org, product, %{firmware | version: "0.5.0"}, %{
          tags: ["beta", "rpi"]
        })

      assert ManagedDeployments.matched_device_ids(deployment_group, in_deployment: false) == [
               device2.id
             ]
    end

    test "when matching on tags, returns any devices that have at least one tag in common with deployment",
         %{
           firmware: firmware,
           org: org,
           product: product
         } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(%{
          conditions: %{
            "tags" => ["beta", "rpi"],
            "version" => ""
          },
          firmware_id: firmware.id,
          is_active: false,
          name: "Deployment 123",
          org_id: org.id,
          product_id: firmware.product_id
        })

      device1 =
        Fixtures.device_fixture(
          org,
          product,
          firmware,
          %{
            tags: ["beta"]
          }
        )

      device2 =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["rpi"]
        })

      device3 =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta", "rpi"]
        })

      device4 =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta", "foo"]
        })

      _device5 =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["foo"]
        })

      matched_ids = ManagedDeployments.matched_device_ids(deployment_group, in_deployment: false)

      assert Enum.sort(matched_ids) ==
               Enum.sort([
                 device1.id,
                 device2.id,
                 device3.id,
                 device4.id
               ])
    end
  end

  test "should_run_orchestrator/0", %{deployment_group: deployment_group} do
    assert [] == ManagedDeployments.should_run_orchestrator()
    {:ok, _} = ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true})
    assert length(ManagedDeployments.should_run_orchestrator()) == 1
  end

  test "get_deployment_groups_by_firmware/1", %{
    firmware: firmware
  } do
    assert [] == ManagedDeployments.get_deployment_groups_by_firmware(123)
    assert length(ManagedDeployments.get_deployment_groups_by_firmware(firmware.id)) == 1
  end

  test "get_deployment_group_for_update/1", %{deployment_group: deployment_group} do
    assert {:ok, %DeploymentGroup{}} =
             ManagedDeployments.get_deployment_group_for_update(%Device{
               deployment_id: deployment_group.id
             })

    assert ManagedDeployments.get_deployment_group_for_update(%Device{deployment_id: 123}) ==
             {:error, :not_found}
  end
end
