defmodule NervesHub.ManagedDeploymentsTest do
  use NervesHub.DataCase, async: false
  use Mimic

  import Phoenix.ChannelTest

  alias Ecto.Changeset
  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentGroup.Conditions
  alias NervesHub.ManagedDeployments.Distributed.Orchestrator, as: DistributedOrchestrator
  alias NervesHub.Workers.FirmwareDeltaBuilder
  alias Phoenix.Socket.Broadcast

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment_group = Fixtures.deployment_group_fixture(firmware)

    user2 = Fixtures.user_fixture(%{email: "user2@test.com"})
    org2 = Fixtures.org_fixture(user2, %{name: "org2"})
    product2 = Fixtures.product_fixture(user2, org2)
    org_key2 = Fixtures.org_key_fixture(org2, user2)
    firmware2 = Fixtures.firmware_fixture(org_key2, product2)

    {:ok,
     %{
       user: user,
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
      product: product,
      firmware: firmware,
      user: user
    } do
      params = %{
        name: "a different name",
        conditions: %{
          version: "< 1.0.0",
          tags: ["beta", "beta-edge"]
        },
        firmware_id: firmware.id
      }

      {:ok, %DeploymentGroup{} = deployment_group} =
        ManagedDeployments.create_deployment_group(params, product, user)

      for key <- Map.keys(params) do
        case Map.get(deployment_group, key) do
          value when %Conditions{} == value ->
            Map.from_struct(value) == Map.get(params, key)

          value ->
            value == Map.get(params, key)
        end
      end
    end

    test "deployments have unique names wrt product", %{
      firmware: firmware,
      product: product,
      deployment_group: existing_deployment_group,
      user: user
    } do
      params = %{
        name: existing_deployment_group.name,
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        firmware_id: firmware.id
      }

      assert {:error, %Ecto.Changeset{errors: [name: {"has already been taken", _}]}} =
               ManagedDeployments.create_deployment_group(params, product, user)
    end

    test "create_deployment_group with invalid parameters fails", %{product: product, firmware: firmware, user: user} do
      params = %{
        name: "",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        firmware_id: firmware.id
      }

      assert {:error, %Changeset{}} = ManagedDeployments.create_deployment_group(params, product, user)
    end

    test "create_deployment_group with non existant firmware fails", %{product: product, user: user} do
      params = %{
        name: "Boop",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        firmware_id: 0
      }

      assert {:error, %Changeset{errors: [firmware_id: {"does not exist", _}]}} =
               ManagedDeployments.create_deployment_group(params, product, user)
    end

    test "create_deployment_group with non existant (empty) firmware fails", %{product: product, user: user} do
      params = %{
        name: "Boop",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        firmware_id: nil
      }

      assert {:error,
              %Changeset{
                errors: [
                  {:firmware_id, {"can't be blank", [validation: :required]}}
                ]
              }} =
               ManagedDeployments.create_deployment_group(params, product, user)
    end

    test "creates release history when deployment group is created with firmware", %{
      product: product,
      firmware: firmware,
      user: user
    } do
      params = %{
        name: "new deployment with release",
        conditions: %{
          version: "< 1.0.0",
          tags: ["beta"]
        },
        firmware_id: firmware.id
      }

      {:ok, deployment_group} = ManagedDeployments.create_deployment_group(params, product, user)

      releases = ManagedDeployments.list_deployment_releases(deployment_group)

      assert length(releases) == 1
      [release] = releases

      assert release.deployment_group_id == deployment_group.id
      assert release.firmware_id == firmware.id
      refute release.archive_id
      assert release.created_by_id == user.id
      assert release.firmware.id == firmware.id
      assert release.user && release.user.id == user.id
    end
  end

  describe "update_deployment_group/3" do
    test "updating firmware sends an update message", %{
      user: user,
      org_key: org_key,
      firmware: firmware,
      product: product
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

      Fixtures.firmware_delta_fixture(firmware, new_firmware)

      params = %{
        name: "my deployment",
        conditions: %{
          "version" => "< 1.0.1",
          "tags" => ["beta", "beta-edge"]
        },
        firmware_id: firmware.id
      }

      {:ok, deployment_group} = ManagedDeployments.create_deployment_group(params, product, user)

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment_group.id}")

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true}, user)

      assert_broadcast("deployments/update", %{}, 500)
    end

    test "starts distributed orchestrator if deployment updates to active from inactive",
         %{
           user: user,
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
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true}, user)

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: false}, user)

      topic = "orchestrator:deployment:#{deployment_group.id}"
      assert_receive %Broadcast{topic: ^topic, event: "deactivated"}, 500
    end

    test "triggers delta generation when firmware is updated and delta updates are enabled",
         %{
           user: user,
           deployment_group: deployment_group,
           firmware: firmware,
           org: org,
           org_key: org_key,
           product: product
         } do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: true}, user)

      assert deployment_group.delta_updatable
      assert deployment_group.firmware_id == firmware.id

      device =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})
        |> Devices.update_deployment_group(deployment_group)

      assert device.deployment_id == deployment_group.id

      new_firmware = Fixtures.firmware_fixture(org_key, product)

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: new_firmware.id}, user)

      assert_enqueued(worker: FirmwareDeltaBuilder, args: %{source_id: firmware.id, target_id: new_firmware.id})
    end

    test "triggers delta generation when delta updates are enabled",
         %{
           user: user,
           deployment_group: deployment_group,
           firmware: firmware,
           org: org,
           org_key: org_key,
           product: product
         } do
      refute deployment_group.delta_updatable
      assert deployment_group.firmware_id == firmware.id

      new_firmware = Fixtures.firmware_fixture(org_key, product)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: new_firmware.id}, user)

      device =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})
        |> Devices.update_deployment_group(deployment_group)

      assert device.deployment_id == deployment_group.id

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: true}, user)

      assert_enqueued(worker: FirmwareDeltaBuilder, args: %{source_id: firmware.id, target_id: new_firmware.id})
    end

    test "does not trigger delta generation if firmware has not changed",
         %{
           user: user,
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

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: true}, user)

      reject(FirmwareDeltaBuilder, :new, 1)
    end

    test "triggers delta generation for every unique device firmware + deployment firmware combination",
         %{
           user: user,
           deployment_group: deployment_group,
           firmware: firmware,
           org: org,
           product: product,
           org_key: org_key
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

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: true}, user)

      assert_enqueued(worker: FirmwareDeltaBuilder, args: %{source_id: firmware2.id, target_id: firmware.id})
      assert_enqueued(worker: FirmwareDeltaBuilder, args: %{source_id: firmware3.id, target_id: firmware.id})
      assert_enqueued(worker: FirmwareDeltaBuilder, args: %{source_id: firmware4.id, target_id: firmware.id})
    end

    test "sets status to :preparing when turning on deltas", %{user: user, deployment_group: deployment_group} do
      assert deployment_group.status == :ready

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: true}, user)

      assert deployment_group.status == :preparing
    end

    test "sets status to :ready when turning off deltas", %{user: user, deployment_group: deployment_group} do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: true}, user)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: false}, user)

      assert deployment_group.status == :ready
    end

    test "creates release record when either firmware or archive change", %{
      user: user,
      deployment_group: deployment_group,
      org_key: org_key,
      product: product
    } do
      # One from the initial creation
      assert length(ManagedDeployments.list_deployment_releases(deployment_group)) == 1

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "3.0.0"})
      archive = Fixtures.archive_fixture(org_key, product, %{version: "1.0.0"})

      {:ok, updated_deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{firmware_id: new_firmware.id, archive_id: archive.id},
          user
        )

      releases = ManagedDeployments.list_deployment_releases(updated_deployment_group)
      assert length(releases) == 2

      [release | _rest] = releases
      assert release.firmware_id == new_firmware.id
      assert release.archive_id == archive.id
      assert release.archive.version == "1.0.0"

      {:ok, updated_deployment_group} =
        ManagedDeployments.update_deployment_group(
          updated_deployment_group,
          %{archive_id: nil},
          user
        )

      releases = ManagedDeployments.list_deployment_releases(updated_deployment_group)
      assert length(releases) == 3
      [latest_release | _rest] = releases
      assert latest_release.archive_id == nil
    end

    test "does not create release record when firmware is not changed", %{
      user: user,
      deployment_group: deployment_group
    } do
      releases = ManagedDeployments.list_deployment_releases(deployment_group)
      assert length(releases) == 1
      # Update something other than firmware
      {:ok, _updated_deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{is_active: true},
          user
        )

      # Should have no new releases
      assert ManagedDeployments.list_deployment_releases(deployment_group) == releases
    end

    test "list_deployment_releases returns releases ordered by most recent first", %{
      user: user,
      deployment_group: deployment_group,
      org_key: org_key,
      product: product
    } do
      # Create several new releases
      Enum.each(["2.0.0", "2.1.0", "2.2.0"], fn version ->
        firmware = Fixtures.firmware_fixture(org_key, product, %{version: version})

        {:ok, updated_dg} =
          ManagedDeployments.update_deployment_group(
            deployment_group,
            %{firmware_id: firmware.id},
            user
          )

        updated_dg
      end)

      releases = ManagedDeployments.list_deployment_releases(deployment_group)
      # 4 because one is created when the deployment group is created
      assert length(releases) == 4

      assert Enum.map(releases, & &1.firmware.version) == ["2.2.0", "2.1.0", "2.0.0", deployment_group.firmware.version]
    end

    test "deployment releases are cascade deleted when deployment group is deleted", %{
      user: user,
      deployment_group: deployment_group,
      org_key: org_key,
      product: product
    } do
      # Create some releases
      firmware1 = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0"})
      firmware2 = Fixtures.firmware_fixture(org_key, product, %{version: "2.1.0"})

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: firmware1.id}, user)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: firmware2.id}, user)

      releases = ManagedDeployments.list_deployment_releases(deployment_group)
      assert length(releases) == 3

      # Delete the deployment group
      {:ok, _deleted} = ManagedDeployments.delete_deployment_group(deployment_group)

      # Verify releases are deleted
      assert ManagedDeployments.list_deployment_releases(deployment_group) == []
    end
  end

  describe "devices matching deployments" do
    test "finds all matching deployments", state do
      %{org: org, product: product, firmware: firmware} = state

      %{id: beta_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "beta",
          conditions: %{"tags" => ["beta"], "version" => ""}
        })

      %{id: rpi_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => ""}
        })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi0"], "version" => ""}
      })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [
               %{id: ^beta_deployment_group_id},
               %{id: ^rpi_deployment_group_id}
             ] = ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployment with no tag condition", state do
      %{org: org, product: product, firmware: firmware} = state

      %{id: blank_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "beta",
          conditions: %{"tags" => [], "version" => ""}
        })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi",
        conditions: %{"tags" => ["rpi"], "version" => ""}
      })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi0"], "version" => ""}
      })

      %{tags: []} = device = Fixtures.device_fixture(org, product, firmware, %{tags: []})

      assert [
               %{id: ^blank_deployment_group_id}
             ] = ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployment when device tags is null", state do
      %{org: org, product: product, firmware: firmware} = state

      %{id: blank_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "beta",
          conditions: %{"tags" => [], "version" => ""}
        })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi",
        conditions: %{"tags" => ["rpi"], "version" => ""}
      })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi0"], "version" => ""}
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
        Fixtures.deployment_group_fixture(rpi_firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => ""}
        })

      Fixtures.deployment_group_fixture(rpi0_firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"], "version" => ""}
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
        Fixtures.deployment_group_fixture(rpi_firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => ""}
        })

      Fixtures.deployment_group_fixture(rpi0_firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"], "version" => ""}
      })

      device = Fixtures.device_fixture(org, product, rpi_firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^rpi_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including the version", state do
      %{org: org, product: product, firmware: firmware} = state

      %{id: low_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => "~> 1.0"}
        })

      Fixtures.deployment_group_fixture(firmware, %{
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
        Fixtures.deployment_group_fixture(firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => "~> 1.0"}
        })

      Fixtures.deployment_group_fixture(firmware, %{
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
        Fixtures.deployment_group_fixture(v100_firmware, %{
          name: v100_firmware.version,
          conditions: %{"version" => "", "tags" => ["next"]}
        })

      %{id: v100rc1_deployment_id} =
        Fixtures.deployment_group_fixture(v100rc1_fw, %{
          name: v100rc1_fw.version,
          conditions: %{"version" => "", "tags" => ["next"]}
        })

      %{id: v100rc2_deployment_id} =
        Fixtures.deployment_group_fixture(v100rc2_fw, %{
          name: v100rc2_fw.version,
          conditions: %{"version" => "", "tags" => ["next"]}
        })

      %{id: v101_deployment_id} =
        Fixtures.deployment_group_fixture(v101_fw, %{
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

    test "matchings tags are prioritized if deployment groups have the same firmware", state do
      %{org: org, product: product, firmware: firmware} = state

      %{id: no_tags_deployment_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "default",
          conditions: %{"tags" => ["testing"], "version" => "> 0.7.0"}
        })

      %{id: matching_tags_deployment_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "alpha",
          conditions: %{"tags" => ["alpha", "testing"], "version" => "<= 1.1.1"}
        })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["alpha", "testing", "foo"]})

      [
        %{id: ^matching_tags_deployment_id},
        %{id: ^no_tags_deployment_id}
      ] =
        ManagedDeployments.matching_deployment_groups(device)
    end

    test "older deployment groups are prioritized if deployment groups have the same firmware and there are no matching tags",
         state do
      %{org: org, product: product, firmware: firmware} = state

      %{id: older_deployment_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "default",
          conditions: %{"tags" => [], "version" => "> 0.7.0"}
        })

      %{id: newer_deployment_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "alpha",
          conditions: %{"tags" => [], "version" => "<= 1.1.1"}
        })

      device = Fixtures.device_fixture(org, product, firmware)

      [
        %{id: ^older_deployment_id},
        %{id: ^newer_deployment_id}
      ] =
        ManagedDeployments.matching_deployment_groups(device)
    end
  end

  describe "verify_deployment_group_membership/1" do
    setup %{org: org, product: product, firmware: firmware} = context do
      Map.put(context, :device, Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]}))
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
        |> Devices.update_firmware_metadata(%{"platform" => "foobar"}, :unknown, false)

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
        |> Devices.update_firmware_metadata(%{"architecture" => "foobar"}, :unknown, false)

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
        |> Devices.update_firmware_metadata(%{"version" => "1.0.1"}, :unknown, false)

      device = ManagedDeployments.verify_deployment_group_membership(device)
      refute device.deployment_id

      [audit_log] = AuditLogs.logs_for(deployment_group)
      assert audit_log.description =~ "no longer matches deployment group"
    end

    test "removes device from deployment group and creates audit log when deployment group version constraint is invalid",
         %{
           device: device,
           deployment_group: deployment_group
         } do
      {:ok, _} =
        deployment_group
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:conditions, %{tags: ["beta", "rpi"], version: "0.1"})
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
    setup %{org: org, product: product, firmware: firmware, user: user} =
            context do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(
          %{
            name: "Deployment 123",
            conditions: %{
              "version" => "> 1.0.0",
              "tags" => []
            },
            firmware_id: firmware.id
          },
          product,
          user
        )

      Fixtures.device_fixture(org, product, firmware, %{
        tags: ["foo"],
        deployment_id: deployment_group.id
      })

      Fixtures.device_fixture(org, product, firmware, %{
        tags: ["beta", "rpi"],
        deployment_id: deployment_group.id
      })

      Fixtures.device_fixture(org, product, %{firmware | version: "1.2.0"}, %{
        tags: ["beta", "rpi"],
        deployment_id: deployment_group.id
      })

      Map.put(context, :deployment_group, deployment_group)
    end

    test "count for deployment group with version but no tags", %{
      deployment_group: deployment_group
    } do
      assert ManagedDeployments.matched_devices_count(deployment_group, in_deployment: true) == 1
    end

    test "counts devices for deployment group with tags but no version", %{
      user: user,
      deployment_group: deployment_group
    } do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            conditions: %{"tags" => ["beta", "rpi"], "version" => ""}
          },
          user
        )

      assert ManagedDeployments.matched_devices_count(deployment_group, in_deployment: true) == 2
    end

    test "counts devices for deployment group with tags and version", %{
      user: user,
      deployment_group: deployment_group
    } do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            conditions: %{"tags" => ["beta", "rpi"], "version" => "> 1.1.0"}
          },
          user
        )

      assert ManagedDeployments.matched_devices_count(deployment_group, in_deployment: true) == 1
    end

    test "accounts for devices outside of deployment group", %{
      user: user,
      deployment_group: deployment_group,
      org: org,
      product: product,
      firmware: firmware
    } do
      device =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta", "rpi"]
        })

      refute device.deployment_id

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            conditions: %{"tags" => ["beta", "rpi"], "version" => ""}
          },
          user
        )

      assert ManagedDeployments.matched_devices_count(deployment_group, in_deployment: false) == 1
    end

    test "devices outside deployment group account for platform and architecture", %{
      user: user,
      deployment_group: deployment_group,
      org: org,
      product: product,
      firmware: firmware
    } do
      device =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta", "rpi"]
        })

      refute device.deployment_id

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            conditions: %{"tags" => ["beta", "rpi"], "version" => ""}
          },
          user
        )

      assert ManagedDeployments.matched_devices_count(deployment_group, in_deployment: false) == 1
    end
  end

  describe "matched_device_ids/2" do
    test "takes platform and architecture into account", %{
      org: org,
      product: product,
      firmware: firmware,
      user: user
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(
          %{
            name: "Deployment 123",
            conditions: %{
              "version" => "1.0.0",
              "tags" => ["beta", "rpi"]
            },
            firmware_id: firmware.id
          },
          product,
          user
        )

      _device1 =
        Fixtures.device_fixture(
          org,
          product,
          %{firmware | platform: "foo", architecture: "bar"},
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
      org: org,
      product: product,
      firmware: firmware,
      user: user
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(
          %{
            name: "Deployment 123",
            conditions: %{
              "version" => "1.0.0",
              "tags" => ["beta", "rpi"]
            },
            firmware_id: firmware.id
          },
          product,
          user
        )

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
      org: org,
      product: product,
      firmware: firmware,
      user: user
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(
          %{
            name: "Deployment 123",
            conditions: %{
              "version" => "",
              "tags" => ["beta", "rpi"]
            },
            firmware_id: firmware.id
          },
          product,
          user
        )

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
      org: org,
      product: product,
      firmware: firmware,
      user: user
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(
          %{
            name: "Deployment 123",
            conditions: %{
              "version" => "< 1.0.0",
              "tags" => []
            },
            firmware_id: firmware.id
          },
          product,
          user
        )

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
           org: org,
           product: product,
           firmware: firmware,
           user: user
         } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(
          %{
            name: "Deployment 123",
            conditions: %{
              "version" => "",
              "tags" => ["beta", "rpi"]
            },
            firmware_id: firmware.id
          },
          product,
          user
        )

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

  test "should_run_orchestrator/0", %{user: user, deployment_group: deployment_group} do
    assert [] == ManagedDeployments.should_run_orchestrator()
    {:ok, _} = ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true}, user)
    assert length(ManagedDeployments.should_run_orchestrator()) == 1
  end

  test "get_deployment_groups_by_firmware/1", %{
    firmware: firmware
  } do
    assert [] == ManagedDeployments.get_deployment_groups_by_firmware(123)
    assert length(ManagedDeployments.get_deployment_groups_by_firmware(firmware.id)) == 1
  end
end
