defmodule NervesHub.ManagedDeploymentsTest do
  use NervesHub.DataCase, async: true
  use Mimic

  import Phoenix.ChannelTest

  alias Ecto.Changeset
  alias NervesHub.AuditLogs
  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Deployments
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentGroup.Conditions
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Orchestrator
  alias NervesHub.Repo
  alias NervesHub.Workers.FirmwareDeltaBuilder
  alias Phoenix.Socket.Broadcast

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    user2 = Fixtures.user_fixture(%{email: "user2@test.com"})
    org2 = Fixtures.org_fixture(user2, %{name: "org2"})
    product2 = Fixtures.product_fixture(user2, org2)
    org_key2 = Fixtures.org_key_fixture(org2, user2, tmp_dir)
    firmware2 = Fixtures.firmware_fixture(org_key2, product2, %{dir: tmp_dir})

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
       product2: product2,
       tmp_dir: tmp_dir
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
        }
      }

      {:ok, %DeploymentGroup{} = deployment_group} =
        ManagedDeployments.create_deployment_group(params, product, firmware, user)

      for key <- Map.keys(params) do
        case Map.get(deployment_group, key) do
          %Conditions{} = value ->
            Map.equal?(Map.from_struct(value), Map.get(params, key))

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
        }
      }

      assert {:error, %Ecto.Changeset{errors: [name: {"has already been taken", _}]}} =
               ManagedDeployments.create_deployment_group(params, product, firmware, user)
    end

    test "create_deployment_group with invalid parameters fails", %{product: product, firmware: firmware, user: user} do
      params = %{
        name: "",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        }
      }

      assert {:error, %Changeset{}} = ManagedDeployments.create_deployment_group(params, product, firmware, user)
    end

    test "create_deployment_group with non existant (empty) firmware fails", %{product: product, user: user} do
      params = %{
        name: "Boop",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        }
      }

      assert {:error,
              %Changeset{
                errors: [
                  {:firmware, {"can't be blank", [validation: :required]}}
                ]
              }} =
               ManagedDeployments.create_deployment_group(params, product, nil, user)
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
        }
      }

      {:ok, deployment_group} = ManagedDeployments.create_deployment_group(params, product, firmware, user)

      releases = ManagedDeployments.list_deployment_releases(deployment_group)

      assert length(releases) == 1
      [release] = releases

      assert release.deployment_group_id == deployment_group.id
      assert release.firmware_id == firmware.id
      refute release.archive_id
      assert release.created_by_id == user.id
      assert release.firmware.id == firmware.id
      assert release.created_by && release.created_by.id == user.id
    end
  end

  describe "update_deployment_group/3" do
    test "updating firmware sends an update message", %{
      user: user,
      org_key: org_key,
      firmware: firmware,
      product: product,
      tmp_dir: tmp_dir
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.1"})

      Fixtures.firmware_delta_fixture(firmware, new_firmware)

      params = %{
        name: "my deployment",
        conditions: %{
          "version" => "< 1.0.1",
          "tags" => ["beta", "beta-edge"]
        }
      }

      {:ok, deployment_group} = ManagedDeployments.create_deployment_group(params, product, firmware, user)

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

      :ok = DeploymentOrchestratorEvents.subscribe(deployment_group)

      stub(
        Orchestrator,
        :start_orchestrator,
        fn _deployment_group -> :ok end
      )

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true}, user)

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: false}, user)

      topic = DeploymentOrchestratorEvents.topic(deployment_group)
      assert_receive %Broadcast{topic: ^topic, event: "deactivated"}, 500
    end

    test "triggers delta generation when firmware is updated and delta updates are enabled",
         %{
           user: user,
           deployment_group: deployment_group,
           firmware: firmware,
           org: org,
           org_key: org_key,
           product: product,
           tmp_dir: tmp_dir
         } do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true, delta_updatable: true}, user)

      assert deployment_group.delta_updatable
      assert deployment_group.current_release.firmware_id == firmware.id

      device =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})
        |> Deployments.update_deployment_group(deployment_group)

      assert device.deployment_id == deployment_group.id

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, _} =
        ManagedDeployments.create_deployment_release(deployment_group, new_firmware, nil, user, %{})

      assert_enqueued(worker: FirmwareDeltaBuilder, args: %{source_id: firmware.id, target_id: new_firmware.id})
    end

    test "triggers delta generation when delta updates are enabled",
         %{
           user: user,
           deployment_group: deployment_group,
           firmware: firmware,
           org: org,
           org_key: org_key,
           product: product,
           tmp_dir: tmp_dir
         } do
      refute deployment_group.delta_updatable
      assert deployment_group.current_release.firmware_id == firmware.id

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, {_release, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, new_firmware, nil, user, %{})

      device =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})
        |> Deployments.update_deployment_group(deployment_group)

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
      assert deployment_group.current_release.firmware_id == firmware.id

      device =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})
        |> Deployments.update_deployment_group(deployment_group)

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
           org_key: org_key,
           tmp_dir: tmp_dir
         } do
      firmware2 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      firmware3 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      firmware4 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      _ =
        Fixtures.device_fixture(org, product, firmware2)
        |> Deployments.update_deployment_group(deployment_group)

      _ =
        Fixtures.device_fixture(org, product, firmware2)
        |> Deployments.update_deployment_group(deployment_group)

      _ =
        Fixtures.device_fixture(org, product, firmware3)
        |> Deployments.update_deployment_group(deployment_group)

      _ =
        Fixtures.device_fixture(org, product, firmware3)
        |> Deployments.update_deployment_group(deployment_group)

      _ =
        Fixtures.device_fixture(org, product, firmware4)
        |> Deployments.update_deployment_group(deployment_group)

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: true}, user)

      assert_enqueued(worker: FirmwareDeltaBuilder, args: %{source_id: firmware2.id, target_id: firmware.id})
      assert_enqueued(worker: FirmwareDeltaBuilder, args: %{source_id: firmware3.id, target_id: firmware.id})
      assert_enqueued(worker: FirmwareDeltaBuilder, args: %{source_id: firmware4.id, target_id: firmware.id})
    end

    test "sets its release's delta status to :ready when turning on deltas but no deltas need to be generated", %{
      user: user,
      deployment_group: deployment_group
    } do
      assert delta_status(deployment_group) == :ready

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true, delta_updatable: true}, user)

      assert delta_status(deployment_group) == :ready
    end

    test "sets its release's delta status to :preparing when turning on deltas and deltas need to be generated", %{
      user: user,
      org: org,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      old_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1", dir: tmp_dir})

      deployment_group = Fixtures.deployment_group_fixture(new_firmware, %{name: "Delta Time", user: user})

      assert delta_status(deployment_group) == :ready

      _device = Fixtures.device_fixture(org, product, old_firmware, %{deployment_id: deployment_group.id})

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true, delta_updatable: true}, user)

      assert delta_status(deployment_group) == :preparing
    end

    test "sets its release's delta status to :ready when deltas are enabled and a new release but their are no devices which require an update",
         %{
           user: user,
           deployment_group: deployment_group,
           product: product,
           org_key: org_key,
           tmp_dir: tmp_dir
         } do
      firmware2 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, deployment_group} =
        deployment_group
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:delta_updatable, true)
        |> Ecto.Changeset.put_change(:is_active, true)
        |> Repo.update()

      assert delta_status(deployment_group) == :ready

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: firmware2.id}, user)

      assert delta_status(deployment_group) == :ready
    end

    test "sets its release's delta status to :ready when deltas are enabled and a new release and deltas already exist",
         %{
           user: user,
           deployment_group: deployment_group,
           org: org,
           product: product,
           org_key: org_key,
           tmp_dir: tmp_dir
         } do
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      %FirmwareDelta{} = Fixtures.firmware_delta_fixture(deployment_group.current_release.firmware, new_firmware)

      %Device{} =
        Fixtures.device_fixture(org, product, deployment_group.current_release.firmware, %{
          deployment_id: deployment_group.id
        })

      {:ok, deployment_group} =
        deployment_group
        |> Ecto.Changeset.change(%{delta_updatable: true, is_active: true})
        |> Repo.update()

      assert delta_status(deployment_group) == :ready

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: new_firmware.id}, user)

      assert delta_status(deployment_group) == :ready
    end

    test "sets its release's delta status to :preparing when deltas are enabled and a new release is created and their are devices on older firmware versions",
         %{
           user: user,
           org: org,
           org_key: org_key,
           product: product,
           tmp_dir: tmp_dir
         } do
      old_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1", dir: tmp_dir})

      deployment_group =
        Fixtures.deployment_group_fixture(old_firmware, %{
          name: "Delta Time",
          is_active: true,
          delta_updatable: true,
          user: user
        })

      assert delta_status(deployment_group) == :ready

      _device = Fixtures.device_fixture(org, product, old_firmware, %{deployment_id: deployment_group.id})

      {:ok, {_release, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, new_firmware, nil, user, %{})

      assert delta_status(deployment_group) == :preparing
    end

    test "doesn't wait on a delta from deleted firmware when a new release is created", %{
      user: user,
      org: org,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      current_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
      deleted_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "0.9.0", dir: tmp_dir})
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1", dir: tmp_dir})

      deployment_group =
        Fixtures.deployment_group_fixture(current_firmware, %{
          name: "Delta Time",
          is_active: true,
          delta_updatable: true,
          user: user
        })

      _device = Fixtures.device_fixture(org, product, deleted_firmware, %{deployment_id: deployment_group.id})
      {:ok, _} = Firmwares.delete_firmware(deleted_firmware, user)

      {:ok, {_release, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, new_firmware, nil, user, %{})

      # The deleted firmware's file is gone, so the device takes the full image
      refute_enqueued(worker: FirmwareDeltaBuilder, args: %{source_id: deleted_firmware.id})
      assert delta_status(deployment_group) == :ready
    end

    test "a delta left over from deleted firmware doesn't hold its release back", %{
      user: user,
      org: org,
      deployment_group: deployment_group,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      deleted_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "0.9.0", dir: tmp_dir})
      _device = Fixtures.device_fixture(org, product, deleted_firmware, %{deployment_id: deployment_group.id})
      {:ok, _} = Firmwares.delete_firmware(deleted_firmware, user)

      # Started after the delete, so the delete had no delta to take with it, and
      # its build is cancelled for want of a source file
      _ =
        Fixtures.firmware_delta_fixture(deleted_firmware, deployment_group.current_release.firmware, %{
          status: :processing
        })

      assert {:ok, %{delta_status: :ready}} =
               ManagedDeployments.recalculate_release_delta_status(deployment_group.current_release)
    end

    test "doesn't set its release's delta status to :preparing when deltas are enabled and other information is updated, but no release is created",
         %{
           user: user,
           deployment_group: deployment_group
         } do
      {:ok, deployment_group} =
        deployment_group
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:delta_updatable, true)
        |> Repo.update()

      assert delta_status(deployment_group) == :ready

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{name: "Chase Waterfalls"}, user)

      assert delta_status(deployment_group) == :ready
    end

    test "sets its release's delta status to :ready when turning off deltas", %{
      user: user,
      deployment_group: deployment_group
    } do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: true}, user)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{delta_updatable: false}, user)

      assert delta_status(deployment_group) == :ready
    end

    test "creates release record when either firmware or archive change", %{
      user: user,
      deployment_group: deployment_group,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      # One from the initial creation
      assert length(ManagedDeployments.list_deployment_releases(deployment_group)) == 1

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "3.0.0"})
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.0"})

      {:ok, {_release, updated_deployment_group}} =
        ManagedDeployments.create_deployment_release(
          deployment_group,
          new_firmware,
          archive,
          user,
          %{}
        )

      releases = ManagedDeployments.list_deployment_releases(updated_deployment_group)
      assert length(releases) == 2

      [release | _rest] = releases
      assert release.firmware_id == new_firmware.id
      assert release.archive_id == archive.id
      assert release.archive.version == "1.0.0"

      {:ok, {_release, updated_deployment_group}} =
        ManagedDeployments.create_deployment_release(
          deployment_group,
          new_firmware,
          nil,
          user,
          %{}
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
      product: product,
      tmp_dir: tmp_dir
    } do
      # Create several new releases
      Enum.each(["2.0.0", "2.1.0", "2.2.0"], fn version ->
        firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: version})

        {:ok, {_release, updated_dg}} =
          ManagedDeployments.create_deployment_release(
            deployment_group,
            firmware,
            nil,
            user,
            %{}
          )

        updated_dg
      end)

      releases = ManagedDeployments.list_deployment_releases(deployment_group)
      # 4 because one is created when the deployment group is created
      assert length(releases) == 4

      assert Enum.map(releases, & &1.firmware.version) == [
               "2.2.0",
               "2.1.0",
               "2.0.0",
               deployment_group.current_release.firmware.version
             ]
    end

    test "deployment releases are cascade deleted when deployment group is deleted", %{
      user: user,
      deployment_group: deployment_group,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      # Create some releases
      firmware1 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "2.0.0"})
      firmware2 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "2.1.0"})

      {:ok, {_release, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, firmware1, nil, user, %{})

      {:ok, {_release, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, firmware2, nil, user, %{})

      releases = ManagedDeployments.list_deployment_releases(deployment_group)
      assert length(releases) == 3

      # Delete the deployment group
      {:ok, _deleted} = ManagedDeployments.delete_deployment_group(deployment_group)

      # Verify releases are deleted
      assert ManagedDeployments.list_deployment_releases(deployment_group) == []
    end

    test "a deployment group with a workflow can be deleted", %{
      user: user,
      deployment_group: deployment_group,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      definition = %{
        "version" => 1,
        "steps" => [%{"name" => "Canary"}, %{"name" => "Sign-off", "type" => "approval_required"}]
      }

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: definition}, user)

      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "2.0.0"})

      {:ok, {_release, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, firmware, nil, user, %{})

      # The releases carry workflow steps, and `deployment_workflow_steps`
      # references them with no action of its own.
      assert Repo.aggregate(DeploymentWorkflowStep, :count) > 0

      assert {:ok, _deleted} = ManagedDeployments.delete_deployment_group(deployment_group)

      assert Repo.aggregate(DeploymentWorkflowStep, :count) == 0
      assert ManagedDeployments.list_deployment_releases(deployment_group) == []
    end
  end

  describe "devices matching deployments" do
    test "finds all matching deployments", state do
      %{user: user, org: org, product: product, firmware: firmware} = state

      %{id: beta_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "beta",
          conditions: %{"tags" => ["beta"], "version" => ""},
          user: user
        })

      %{id: rpi_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => ""},
          user: user
        })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi0"], "version" => ""},
        user: user
      })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [
               %{id: ^beta_deployment_group_id},
               %{id: ^rpi_deployment_group_id}
             ] = ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployment with no tag condition", state do
      %{user: user, org: org, product: product, firmware: firmware} = state

      %{id: blank_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "beta",
          conditions: %{"tags" => [], "version" => ""},
          user: user
        })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi",
        conditions: %{"tags" => ["rpi"], "version" => ""},
        user: user
      })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi0"], "version" => ""},
        user: user
      })

      %{tags: []} = device = Fixtures.device_fixture(org, product, firmware, %{tags: []})

      assert [
               %{id: ^blank_deployment_group_id}
             ] = ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployment when device tags is null", state do
      %{user: user, org: org, product: product, firmware: firmware} = state

      %{id: blank_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "beta",
          conditions: %{"tags" => [], "version" => ""},
          user: user
        })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi",
        conditions: %{"tags" => ["rpi"], "version" => ""},
        user: user
      })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi0"], "version" => ""},
        user: user
      })

      %{tags: nil} = device = Fixtures.device_fixture(org, product, firmware, %{tags: nil})

      assert [
               %{id: ^blank_deployment_group_id}
             ] = ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including the platform", state do
      %{user: user, org: org, org_key: org_key, product: product, tmp_dir: tmp_dir} = state

      rpi_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, platform: "rpi"})
      rpi0_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, platform: "rpi0"})

      %{id: rpi_deployment_group_id} =
        Fixtures.deployment_group_fixture(rpi_firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => ""},
          user: user
        })

      Fixtures.deployment_group_fixture(rpi0_firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"], "version" => ""},
        user: user
      })

      device = Fixtures.device_fixture(org, product, rpi_firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^rpi_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including the architecture", state do
      %{user: user, org: org, org_key: org_key, product: product, tmp_dir: tmp_dir} = state

      rpi_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, architecture: "rpi"})
      rpi0_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, architecture: "rpi0"})

      %{id: rpi_deployment_group_id} =
        Fixtures.deployment_group_fixture(rpi_firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => ""},
          user: user
        })

      Fixtures.deployment_group_fixture(rpi0_firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"], "version" => ""},
        user: user
      })

      device = Fixtures.device_fixture(org, product, rpi_firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^rpi_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including the version", state do
      %{user: user, org: org, product: product, firmware: firmware} = state

      %{id: low_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => "~> 1.0"},
          user: user
        })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"], "version" => "~> 2.0"},
        user: user
      })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^low_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds matching deployments including pre versions", state do
      %{user: user, org: org, org_key: org_key, product: product, firmware: firmware, tmp_dir: tmp_dir} = state

      %{id: low_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => "~> 1.0"},
          user: user
        })

      Fixtures.deployment_group_fixture(firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"], "version" => "~> 2.0"},
        user: user
      })

      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.2.0-pre"})

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^low_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "finds the newest firmware version including pre-releases", state do
      %{
        user: user,
        org: org,
        org_key: org_key,
        product: product,
        firmware: %{version: "1.0.0"} = v100_firmware,
        tmp_dir: tmp_dir
      } = state

      v090_fw = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "0.9.0"})
      v100rc1_fw = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.0-rc.1"})
      v100rc2_fw = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.0-rc.2"})
      v101_fw = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.1"})

      %{id: v100_deployment_id} =
        Fixtures.deployment_group_fixture(v100_firmware, %{
          name: v100_firmware.version,
          conditions: %{"version" => "", "tags" => ["next"]},
          user: user
        })

      %{id: v100rc1_deployment_id} =
        Fixtures.deployment_group_fixture(v100rc1_fw, %{
          name: v100rc1_fw.version,
          conditions: %{"version" => "", "tags" => ["next"]},
          user: user
        })

      %{id: v100rc2_deployment_id} =
        Fixtures.deployment_group_fixture(v100rc2_fw, %{
          name: v100rc2_fw.version,
          conditions: %{"version" => "", "tags" => ["next"]},
          user: user
        })

      %{id: v101_deployment_id} =
        Fixtures.deployment_group_fixture(v101_fw, %{
          name: v101_fw.version,
          conditions: %{"version" => "", "tags" => ["next"]},
          user: user
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

    test "matchings tags are prioritized if deployment groups have the same firmware and one has no tags", state do
      %{user: user, org: org, product: product, firmware: firmware} = state

      %{id: no_tags_deployment_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "default",
          conditions: %{"tags" => [], "version" => "> 0.7.0"},
          user: user
        })

      %{id: matching_tags_deployment_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "alpha",
          conditions: %{"tags" => ["alpha"], "version" => "<= 1.1.1"},
          user: user
        })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["alpha", "testing"]})

      [
        %{id: ^matching_tags_deployment_id},
        %{id: ^no_tags_deployment_id}
      ] =
        ManagedDeployments.matching_deployment_groups(device)
    end

    test "the deployment with the most matching tags are prioritized if deployment groups have the same firmware",
         state do
      %{user: user, org: org, product: product, firmware: firmware} = state

      %{id: no_tags_deployment_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "default",
          conditions: %{"tags" => ["testing"], "version" => "> 0.7.0"},
          user: user
        })

      %{id: matching_tags_deployment_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "alpha",
          conditions: %{"tags" => ["alpha", "testing"], "version" => "<= 1.1.1"},
          user: user
        })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["alpha", "testing"]})

      [
        %{id: ^matching_tags_deployment_id},
        %{id: ^no_tags_deployment_id}
      ] =
        ManagedDeployments.matching_deployment_groups(device)
    end

    test "older deployment groups are prioritized if they have the same firmware and there are no matching tags",
         state do
      %{user: user, org: org, product: product, firmware: firmware, deployment_group: %{id: oldest_id}} =
        state

      %DeploymentGroup{id: older_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "default",
          conditions: %{"tags" => [], "version" => "> 0.7.0"},
          user: user
        })

      %DeploymentGroup{id: newest_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "alpha",
          conditions: %{"tags" => [], "version" => "<= 1.1.1"},
          user: user
        })

      device = Fixtures.device_fixture(org, product, firmware)

      [
        %{id: ^oldest_id},
        %{id: ^older_id},
        %{id: ^newest_id}
      ] =
        ManagedDeployments.matching_deployment_groups(device)
    end

    test "older deployment groups are prioritized when there are the same number of matching tags",
         state do
      %{user: user, org: org, product: product, firmware: firmware} = state

      %{id: older_deployment_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "default",
          conditions: %{"tags" => ["foo", "bar"], "version" => "> 0.7.0"},
          user: user
        })

      %{id: newest_deployment_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "alpha",
          conditions: %{"tags" => ["foo", "bar"], "version" => "<= 1.1.1"},
          user: user
        })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo", "bar", "baz"]})

      [
        %{id: ^older_deployment_id},
        %{id: ^newest_deployment_id}
      ] =
        ManagedDeployments.matching_deployment_groups(device)
    end

    test "'Allow any' matches devices that have at least one of the tags", state do
      %{user: user, org: org, product: product, firmware: firmware} = state

      %{id: any_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "any",
          conditions: %{"tags" => ["unique-a", "unique-b"], "version" => "", "tag_operator" => "or"},
          user: user
        })

      # device has only one of the two tags, which is enough for "Allow any"
      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["unique-a"]})

      assert [%{id: ^any_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(device)
    end

    test "'Require all' only matches devices that have every tag", state do
      %{user: user, org: org, product: product, firmware: firmware} = state

      %{id: all_deployment_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "all",
          conditions: %{"tags" => ["unique-a", "unique-b"], "version" => "", "tag_operator" => "and"},
          user: user
        })

      # device only has one of the two required tags
      partial_device = Fixtures.device_fixture(org, product, firmware, %{tags: ["unique-a"]})
      assert [] = ManagedDeployments.matching_deployment_groups(partial_device)

      # device has all of the required tags (plus an extra)
      full_device =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["unique-a", "unique-b", "extra"]})

      assert [%{id: ^all_deployment_group_id}] =
               ManagedDeployments.matching_deployment_groups(full_device)
    end

    test "tag matching defaults to 'Require all'", state do
      %{user: user, firmware: firmware} = state

      deployment_group =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "defaulted",
          conditions: %{"tags" => ["beta"], "version" => ""},
          user: user
        })

      assert deployment_group.conditions.tag_operator == :and
    end

    test "excludes deployment groups with lock_device_membership enabled", state do
      %{user: user, org: org, product: product, firmware: firmware} = state

      %{id: open_group_id} =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "open",
          conditions: %{"tags" => ["beta"], "version" => ""},
          user: user
        })

      locked_group =
        Fixtures.deployment_group_fixture(firmware, %{
          name: "locked",
          conditions: %{"tags" => ["beta"], "version" => ""},
          user: user
        })

      {:ok, _} =
        locked_group
        |> Ecto.Changeset.change(%{lock_device_membership: true})
        |> NervesHub.Repo.update()

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

      assert [%{id: ^open_group_id}] = ManagedDeployments.matching_deployment_groups(device)
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
      device = Deployments.update_deployment_group(device, deployment_group)
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
        |> Deployments.update_deployment_group(deployment_group)
        |> Devices.update_firmware_metadata(%{"platform" => "foobar"}, :unknown, false)

      device = ManagedDeployments.verify_deployment_group_membership(device)
      refute device.deployment_id

      [audit_log | _] = AuditLogs.logs_for(deployment_group)
      assert audit_log.description =~ "no longer matches deployment"
    end

    test "removes device from deployment group and creates audit log when architecture doesn't match",
         %{
           device: device,
           deployment_group: deployment_group
         } do
      {:ok, device} =
        device
        |> Deployments.update_deployment_group(deployment_group)
        |> Devices.update_firmware_metadata(%{"architecture" => "foobar"}, :unknown, false)

      device = ManagedDeployments.verify_deployment_group_membership(device)
      refute device.deployment_id

      [audit_log | _] = AuditLogs.logs_for(deployment_group)
      assert audit_log.description =~ "no longer matches deployment group"
    end

    test "removes device from deployment group and creates audit log when versions don't match",
         %{
           device: device,
           deployment_group: deployment_group
         } do
      {:ok, device} =
        device
        |> Deployments.update_deployment_group(deployment_group)
        |> Devices.update_firmware_metadata(%{"version" => "1.0.1"}, :unknown, false)

      device = ManagedDeployments.verify_deployment_group_membership(device)
      refute device.deployment_id

      [audit_log | _] = AuditLogs.logs_for(deployment_group)
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

      device = Deployments.update_deployment_group(device, deployment_group)

      device = ManagedDeployments.verify_deployment_group_membership(device)
      refute device.deployment_id

      [audit_log | _] = AuditLogs.logs_for(deployment_group)
      assert audit_log.description =~ "no longer matches deployment group"
    end

    test "does nothing when lock_device_membership is true, even when conditions don't match",
         %{
           device: device,
           deployment_group: deployment_group
         } do
      {:ok, deployment_group} =
        deployment_group
        |> Ecto.Changeset.change(%{lock_device_membership: true})
        |> Repo.update()

      {:ok, device} =
        device
        |> Deployments.update_deployment_group(deployment_group)
        |> Devices.update_firmware_metadata(%{"platform" => "foobar"}, :unknown, false)

      device = ManagedDeployments.verify_deployment_group_membership(device)
      assert device.deployment_id == deployment_group.id
    end
  end

  describe "matched_devices_counts/1" do
    setup %{org: org, product: product, firmware: firmware, user: user} =
            context do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(
          %{
            name: "Deployment 123",
            conditions: %{
              "version" => "> 1.0.0",
              "tags" => []
            }
          },
          product,
          firmware,
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
      assert ManagedDeployments.matched_devices_counts(deployment_group).matched_in_group == 1
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

      assert ManagedDeployments.matched_devices_counts(deployment_group).matched_in_group == 2
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

      assert ManagedDeployments.matched_devices_counts(deployment_group).matched_in_group == 1
    end

    test "'Allow any' counts devices with any of the tags", %{
      user: user,
      deployment_group: deployment_group
    } do
      # setup devices: one ["foo"], two ["beta", "rpi"]
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            conditions: %{"tags" => ["foo", "beta"], "version" => "", "tag_operator" => "or"}
          },
          user
        )

      # ["foo"] matches via foo, both ["beta", "rpi"] match via beta
      assert ManagedDeployments.matched_devices_counts(deployment_group).matched_in_group == 3
    end

    test "'Require all' only counts devices that have every tag", %{
      user: user,
      deployment_group: deployment_group
    } do
      # setup devices: one ["foo"], two ["beta", "rpi"]
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            conditions: %{"tags" => ["beta", "rpi"], "version" => "", "tag_operator" => "and"}
          },
          user
        )

      # only the two ["beta", "rpi"] devices have both tags
      assert ManagedDeployments.matched_devices_counts(deployment_group).matched_in_group == 2
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

      assert ManagedDeployments.matched_devices_counts(deployment_group).matched_outside_group == 1
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

      assert ManagedDeployments.matched_devices_counts(deployment_group).matched_outside_group == 1
    end
  end

  describe "matched_devices_query/2" do
    test "selects the matching devices inside or outside the group", %{
      org: org,
      product: product,
      firmware: firmware,
      user: user
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(
          %{name: "Query match", conditions: %{"version" => "", "tags" => ["beta"], "tag_operator" => "or"}},
          product,
          firmware,
          user
        )

      matching = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})
      _other_tags = Fixtures.device_fixture(org, product, firmware, %{tags: ["prod"]})
      _other_firmware = Fixtures.device_fixture(org, product, %{firmware | platform: "foo"}, %{tags: ["beta"]})
      kept = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"], deployment_id: deployment_group.id})

      assert deployment_group
             |> ManagedDeployments.matched_devices_query(in_deployment: false)
             |> select([d], d.id)
             |> Repo.all() ==
               [matching.id]

      assert deployment_group
             |> ManagedDeployments.matched_devices_query(in_deployment: true)
             |> select([d], d.id)
             |> Repo.all() ==
               [kept.id]
    end
  end

  describe "matching a version requirement" do
    @versions ["0.9.0", "1.0.0", "1.0.0+build.1", "1.1.0-rc.1", "1.1.0", "1.9.9", "2.0.0-rc.1", "2.0.0", "2.1.3"]

    setup %{org: org, product: product, firmware: firmware} do
      devices =
        Map.new(@versions, fn version ->
          {version, Fixtures.device_fixture(org, product, %{firmware | version: version})}
        end)

      %{devices: devices}
    end

    for requirement <- ["~> 1.0", "~> 1.1.0", "~> 2.0", ">= 1.1.0 and < 2.0.0", "< 1.0.0 or > 2.0.0", "== 1.0.0"] do
      test "selects and counts the devices Version.match?/2 does for #{requirement}", %{
        product: product,
        firmware: firmware,
        user: user,
        devices: devices
      } do
        deployment_group = version_group(unquote(requirement), product, firmware, user)

        expected =
          for {version, device} <- devices, Version.match?(version, unquote(requirement)) do
            device.id
          end

        assert Enum.sort(matched_ids(deployment_group, in_deployment: false)) == Enum.sort(expected)

        assert ManagedDeployments.matched_devices_counts(deployment_group).matched_outside_group ==
                 length(expected)
      end
    end

    test "a device with a missing or invalid version never matches", %{
      org: org,
      product: product,
      firmware: firmware,
      user: user,
      devices: devices
    } do
      for version <- [nil, "not-a-version", "01.0.0"] do
        device = Fixtures.device_fixture(org, product, firmware)

        Device
        |> where([d], d.id == ^device.id)
        |> Repo.update_all(set: [firmware_metadata: %{device.firmware_metadata | version: version}])
      end

      deployment_group = version_group(">= 0.0.0", product, firmware, user)

      assert Enum.sort(matched_ids(deployment_group, in_deployment: false)) ==
               devices |> Map.values() |> Enum.map(& &1.id) |> Enum.sort()

      assert ManagedDeployments.matched_devices_counts(deployment_group).matched_outside_group ==
               map_size(devices)
    end
  end

  defp version_group(requirement, product, firmware, user) do
    {:ok, deployment_group} =
      ManagedDeployments.create_deployment_group(
        %{name: "Version #{requirement}", conditions: %{"version" => requirement, "tags" => []}},
        product,
        firmware,
        user
      )

    deployment_group
  end

  describe "remove_unmatched_devices_from_deployment_group/2 notifications" do
    test "tells removed devices in batches, not all at once", %{
      org: org,
      product: product,
      firmware: firmware,
      user: user
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(
          %{name: "Batched remove", conditions: %{"version" => "", "tags" => ["keep"]}},
          product,
          firmware,
          user
        )

      # None match, and there's one more than a batch, so the last device to be
      # told is in the second batch. Inserted in one statement, since a fixture
      # each would take most of a minute.
      template = Fixtures.device_fixture(org, product, firmware, %{tags: ["drop"], deployment_id: deployment_group.id})
      now = NaiveDateTime.utc_now(:second)

      rows =
        for n <- 1..2_500 do
          %{
            org_id: org.id,
            product_id: product.id,
            deployment_id: deployment_group.id,
            tags: ["drop"],
            identifier: "batched-remove-#{System.unique_integer([:positive])}-#{n}",
            firmware_metadata: template.firmware_metadata,
            inserted_at: now,
            updated_at: now
          }
        end

      {2_500, inserted} = Repo.insert_all(Device, rows, returning: [:id])
      devices = [template | Enum.map(inserted, &%Device{id: &1.id})]

      heard = listen_for_group_change(devices, nil)

      matched = ManagedDeployments.matched_devices_query(deployment_group, in_deployment: true)

      {:ok, %{updated: 2_501}} = Deployments.remove_unmatched_devices_from_deployment_group(matched, deployment_group)
      returned_at = System.monotonic_time(:millisecond)

      times = assert_told_in_batches(heard, length(devices))

      # The caller isn't held up for the announcement: it has its answer before
      # the second batch is told
      assert returned_at < List.last(times)
    end
  end

  describe "remove_unmatched_devices_from_deployment_group/2 chunking" do
    test "removes a chunk of devices to a statement, and keeps the ones that match", %{
      org: org,
      product: product,
      firmware: firmware,
      user: user
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(
          %{name: "Chunked remove", conditions: %{"version" => "", "tags" => ["keep"]}},
          product,
          firmware,
          user
        )

      kept = Fixtures.device_fixture(org, product, firmware, %{tags: ["keep"], deployment_id: deployment_group.id})

      # One more than a chunk that doesn't match, so the remove takes two
      template = Fixtures.device_fixture(org, product, firmware, %{tags: ["drop"], deployment_id: deployment_group.id})
      now = NaiveDateTime.utc_now(:second)

      rows =
        for n <- 1..5_000 do
          %{
            org_id: org.id,
            product_id: product.id,
            deployment_id: deployment_group.id,
            tags: ["drop"],
            identifier: "chunked-remove-#{System.unique_integer([:positive])}-#{n}",
            firmware_metadata: template.firmware_metadata,
            inserted_at: now,
            updated_at: now
          }
        end

      {5_000, _} = Repo.insert_all(Device, rows)

      test_pid = self()
      updates = :counters.new(1, [])
      handler_id = "chunked-remove-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:nerves_hub, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if self() == test_pid and String.starts_with?(query, ~s|UPDATE "devices"|),
            do: :counters.add(updates, 1, 1)
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      matched = ManagedDeployments.matched_devices_query(deployment_group, in_deployment: true)

      assert {:ok, %{updated: 5_001}} =
               Deployments.remove_unmatched_devices_from_deployment_group(matched, deployment_group)

      assert :counters.get(updates, 1) == 2
      assert Repo.reload(kept).deployment_id == deployment_group.id
      refute Repo.reload(template).deployment_id
      assert Repo.aggregate(where(Device, [d], d.deployment_id == ^deployment_group.id), :count) == 1
    end
  end

  describe "remove_unmatched_devices_from_deployment_group/2 given a query" do
    test "keeps the devices the query selects, without loading their ids", %{
      org: org,
      product: product,
      firmware: firmware,
      user: user
    } do
      {:ok, deployment_group} =
        ManagedDeployments.create_deployment_group(
          %{name: "Query remove", conditions: %{"version" => "", "tags" => ["beta"]}},
          product,
          firmware,
          user
        )

      kept = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"], deployment_id: deployment_group.id})
      removed = Fixtures.device_fixture(org, product, firmware, %{tags: ["prod"], deployment_id: deployment_group.id})

      test_pid = self()
      handler_id = "query-remove-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:nerves_hub, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if self() == test_pid, do: send(test_pid, {:query, query})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      matched = ManagedDeployments.matched_devices_query(deployment_group, in_deployment: true)

      assert {:ok, %{updated: 1}} =
               Deployments.remove_unmatched_devices_from_deployment_group(matched, deployment_group)

      assert Repo.reload(kept).deployment_id == deployment_group.id
      refute Repo.reload(removed).deployment_id

      # The ids read are the ones to remove. The kept devices are compared
      # against in that query itself, so their ids are never loaded.
      queries = collect_queries([])
      id_reads = Enum.filter(queries, &String.starts_with?(&1, ~s|SELECT d0."id" FROM "devices"|))

      assert Enum.any?(queries, &String.starts_with?(&1, ~s|UPDATE "devices"|))
      assert id_reads != []
      assert Enum.all?(id_reads, &(&1 =~ ~r/NOT \(d0\."id" = ANY\(SELECT|NOT \(d0\."id" IN \(SELECT/))
    end
  end

  describe "matched_devices_query/2 matching rules" do
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
            }
          },
          product,
          firmware,
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

      assert matched_ids(deployment_group, in_deployment: false) == [
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
            }
          },
          product,
          firmware,
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

      assert matched_ids(deployment_group, in_deployment: false) == [
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
            }
          },
          product,
          firmware,
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

      device_ids = matched_ids(deployment_group, in_deployment: false)

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
            }
          },
          product,
          firmware,
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

      assert matched_ids(deployment_group, in_deployment: false) == [
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
              "tags" => ["beta", "rpi"],
              "tag_operator" => "or"
            }
          },
          product,
          firmware,
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

      matched_ids = matched_ids(deployment_group, in_deployment: false)

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

  describe "get_by_product_and_platforms/2" do
    test "returns deployment groups matching any of the given platforms", %{
      product: product,
      deployment_group: deployment_group,
      firmware: firmware
    } do
      result = ManagedDeployments.get_by_product_and_platforms(product, [firmware.platform])

      assert length(result) == 1
      assert hd(result).id == deployment_group.id
    end

    test "returns empty list when no platforms match", %{product: product} do
      assert [] == ManagedDeployments.get_by_product_and_platforms(product, ["nonexistent"])
    end

    test "returns empty list for empty platforms list", %{product: product} do
      assert [] == ManagedDeployments.get_by_product_and_platforms(product, [])
    end

    test "does not return deployment groups from other products", %{
      firmware: firmware,
      product2: product2
    } do
      assert [] == ManagedDeployments.get_by_product_and_platforms(product2, [firmware.platform])
    end

    test "returns deployment groups for multiple platforms", %{
      product: product,
      org_key: org_key,
      deployment_group: deployment_group,
      firmware: firmware,
      user: user,
      tmp_dir: tmp_dir
    } do
      other_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, platform: "rpi0"})
      other_dg = Fixtures.deployment_group_fixture(other_firmware, %{name: "RPi0 Deployment", user: user})

      result = ManagedDeployments.get_by_product_and_platforms(product, [firmware.platform, "rpi0"])

      ids = Enum.map(result, & &1.id)
      assert deployment_group.id in ids
      assert other_dg.id in ids
    end
  end

  # The banner on the group page reads this straight off the preloaded release
  defp delta_status(deployment_group) do
    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group)
    deployment_group.current_release.delta_status
  end

  # Starts a listener on every device's topic. Each notes when its device heard
  # it was moved to `group_id` (or out of its group, for `nil`), rather than when
  # this test gets round to reading it, which on a loaded runner can be later.
  defp listen_for_group_change(devices, group_id) do
    test_pid = self()
    ref = make_ref()

    for device <- devices do
      topic = "device:#{device.id}"

      spawn_link(fn ->
        :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)
        send(test_pid, {:listening, ref})

        receive do
          %Broadcast{topic: ^topic, event: "deployment_updated", payload: %{deployment_id: ^group_id}} ->
            send(test_pid, {:heard, ref, System.monotonic_time(:millisecond)})
        end
      end)
    end

    for _ <- devices, do: assert_receive({:listening, ^ref})

    ref
  end

  # Every device is told once, and the times they heard split into a group of
  # 2,500 and the rest, with the pause between batches between them. The
  # batches follow the order the database returns ids in, so this can't say
  # which device is in which, only that the split is there.
  defp assert_told_in_batches(ref, count) do
    times =
      for _ <- 1..count do
        assert_receive {:heard, ^ref, at}, 2_000
        at
      end
      |> Enum.sort()

    refute_receive {:heard, ^ref, _}, 100

    {first_batch, rest} = Enum.split(times, 2_500)
    assert List.first(rest) - List.last(first_batch) >= 50

    times
  end

  defp matched_ids(deployment_group, opts) do
    deployment_group
    |> ManagedDeployments.matched_devices_query(opts)
    |> select([d], d.id)
    |> order_by([d], asc: d.id)
    |> Repo.all()
  end

  defp collect_queries(acc) do
    receive do
      {:query, query} -> collect_queries([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
