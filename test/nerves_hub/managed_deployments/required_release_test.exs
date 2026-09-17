defmodule NervesHub.ManagedDeployments.RequiredReleaseTest do
  use NervesHub.DataCase, async: true
  use Mimic

  import Ecto.Query, only: [select: 3]

  alias NervesHub.AuditLogs
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Deployments
  alias NervesHub.Devices.Updates
  alias NervesHub.Firmwares
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

    [fw1, fw2, fw3] =
      for version <- ["1.0.0", "2.0.0", "3.0.0"] do
        Fixtures.firmware_fixture(org_key, product, %{version: version, dir: tmp_dir})
      end

    deployment_group = Fixtures.deployment_group_fixture(fw1, %{is_active: true, user: user})

    %{
      user: user,
      org: org,
      product: product,
      org_key: org_key,
      fw1: fw1,
      fw2: fw2,
      fw3: fw3,
      deployment_group: deployment_group
    }
  end

  # Release 1 (fw1, the group's first) -> release 2 (fw2) -> release 3 (fw3, current)
  defp add_releases(%{deployment_group: deployment_group, user: user, fw2: fw2, fw3: fw3}, required \\ [2]) do
    {:ok, {release2, deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, fw2, nil, user, %{required: 2 in required})

    {:ok, {release3, deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, fw3, nil, user, %{required: 3 in required})

    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group)

    %{deployment_group: deployment_group, release2: release2, release3: release3}
  end

  defp connected_device(%{org: org, product: product}, deployment_group, firmware, params \\ %{}) do
    params = Map.merge(%{status: :provisioned, deployment_id: deployment_group.id}, params)
    device = Fixtures.device_fixture(org, product, firmware, params)

    _ = Fixtures.device_connection_fixture(device)
    device
  end

  # The banner on the group page reads this straight off the preloaded release
  defp delta_status(deployment_group) do
    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group)
    deployment_group.current_release.delta_status
  end

  defp run_unknown_firmware(device, version) do
    metadata = Map.from_struct(%{device.firmware_metadata | uuid: Ecto.UUID.generate(), version: version})
    {:ok, device} = Devices.update_firmware_metadata(device, metadata, :unknown, false)
    device
  end

  describe "target_release/2" do
    test "is the current release when no release is required", context do
      %{deployment_group: deployment_group, release3: release3} = add_releases(context, [])
      device = connected_device(context, deployment_group, context.fw1)

      assert ManagedDeployments.target_release(deployment_group, device).id == release3.id
    end

    test "is a required release the device hasn't reached yet", context do
      %{deployment_group: deployment_group, release2: release2} = add_releases(context)
      device = connected_device(context, deployment_group, context.fw1)

      target = ManagedDeployments.target_release(deployment_group, device)

      assert target.id == release2.id
      assert target.firmware.uuid == context.fw2.uuid
    end

    test "moves past a required release once the device is running it", context do
      %{deployment_group: deployment_group, release3: release3} = add_releases(context)
      device = connected_device(context, deployment_group, context.fw2)

      assert ManagedDeployments.target_release(deployment_group, device).id == release3.id
    end

    test "is the earliest of several required releases the device is behind", context do
      {:ok, {release2, deployment_group}} =
        ManagedDeployments.create_deployment_release(
          context.deployment_group,
          context.fw2,
          nil,
          context.user,
          %{required: true}
        )

      {:ok, {release3, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, context.fw3, nil, context.user, %{required: true})

      {:ok, {_release4, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, context.fw1, nil, context.user, %{})

      {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group)

      device = connected_device(context, deployment_group, context.fw2)
      assert ManagedDeployments.target_release(deployment_group, device).id == release3.id

      device = context |> connected_device(deployment_group, context.fw2) |> run_unknown_firmware("0.1.0")
      assert ManagedDeployments.target_release(deployment_group, device).id == release2.id
    end

    test "applies to a device on firmware from no release when its version is behind", context do
      %{deployment_group: deployment_group, release2: release2} = add_releases(context)

      device = context |> connected_device(deployment_group, context.fw1) |> run_unknown_firmware("1.5.0")

      assert ManagedDeployments.target_release(deployment_group, device).id == release2.id
    end

    test "skips a required release a device on firmware from no release is already beyond", context do
      %{deployment_group: deployment_group, release3: release3} = add_releases(context)

      device = context |> connected_device(deployment_group, context.fw1) |> run_unknown_firmware("2.0.0")

      assert ManagedDeployments.target_release(deployment_group, device).id == release3.id
    end

    test "is only worked out per device when an earlier release is required", context do
      %{deployment_group: deployment_group, release2: release2, release3: release3} = add_releases(context, [])
      refute ManagedDeployments.earlier_required_release?(deployment_group)

      {:ok, _} = ManagedDeployments.set_deployment_release_required(release3, true, context.user)
      refute ManagedDeployments.earlier_required_release?(deployment_group)

      {:ok, _} = ManagedDeployments.set_deployment_release_required(release2, true, context.user)
      assert ManagedDeployments.earlier_required_release?(deployment_group)
    end

    test "asks the database once when the answer is loaded onto the group", context do
      %{deployment_group: deployment_group, release2: release2} = add_releases(context, [])
      refute ManagedDeployments.earlier_required_release?(deployment_group)

      loaded = ManagedDeployments.load_earlier_required_release(deployment_group)
      refute ManagedDeployments.earlier_required_release?(loaded)

      {:ok, _} = ManagedDeployments.set_deployment_release_required(release2, true, context.user)

      # The loaded group answers from its snapshot, which is what keeps a pass
      # over a workflow's steps from asking the same question for every step
      refute ManagedDeployments.earlier_required_release?(loaded)
      assert ManagedDeployments.earlier_required_release?(deployment_group)
      assert ManagedDeployments.earlier_required_release?(ManagedDeployments.load_earlier_required_release(loaded))
    end

    test "still applies when the device's version can't be compared", context do
      %{deployment_group: deployment_group, release2: release2} = add_releases(context)

      device = context |> connected_device(deployment_group, context.fw1) |> run_unknown_firmware("not-semver")

      assert ManagedDeployments.target_release(deployment_group, device).id == release2.id
    end
  end

  describe "the update pipeline" do
    test "offers the orchestrator devices behind a required release", context do
      %{deployment_group: deployment_group} = add_releases(context)

      %{id: behind_id} = connected_device(context, deployment_group, context.fw1)
      %{id: on_required_id} = connected_device(context, deployment_group, context.fw2)
      _up_to_date = connected_device(context, deployment_group, context.fw3)

      assert deployment_group |> Updates.available_for_update(10) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([behind_id, on_required_id])
    end

    test "resolves and checks the required release's firmware", context do
      %{deployment_group: deployment_group} = add_releases(context)
      device = connected_device(context, deployment_group, context.fw1)

      payload = Updates.resolve_update(device)
      assert payload.update_available
      assert payload.firmware_meta.uuid == context.fw2.uuid

      assert %{available?: true, firmware_meta: %{uuid: uuid}} = Updates.check_update(device)
      assert uuid == context.fw2.uuid
    end

    test "records the required release's firmware on the inflight update", context do
      %{deployment_group: deployment_group} = add_releases(context)
      device = connected_device(context, deployment_group, context.fw1)

      {:ok, inflight_update} = DeviceEvents.schedule_update(device.id, deployment_group)

      assert inflight_update.firmware_id == context.fw2.id
      assert inflight_update.firmware_uuid == context.fw2.uuid
    end

    test "waits for the delta to the required release, not the one to the current release", context do
      %{deployment_group: deployment_group} = add_releases(context)
      %{id: device_id} = connected_device(context, deployment_group, context.fw1)

      _ = Fixtures.firmware_delta_fixture(context.fw1, context.fw3, %{status: :processing})
      assert [%{id: ^device_id}] = Updates.available_for_update(deployment_group, 10)

      _ = Fixtures.firmware_delta_fixture(context.fw1, context.fw2, %{status: :processing})
      assert [] = Updates.available_for_update(deployment_group, 10)
    end

    test "works out a release's delta status from the deltas its own devices need", context do
      %{deployment_group: deployment_group, release2: release2} = add_releases(context)
      _ = connected_device(context, deployment_group, context.fw1)

      # The device is headed for release 2, so a delta to the current release's
      # firmware is nothing release 2 is waiting on
      _ = Fixtures.firmware_delta_fixture(context.fw1, context.fw3, %{status: :processing})
      assert {:ok, %{delta_status: :ready}} = ManagedDeployments.recalculate_release_delta_status(release2)

      delta = Fixtures.firmware_delta_fixture(context.fw1, context.fw2, %{status: :processing})
      assert {:ok, %{delta_status: :preparing}} = ManagedDeployments.recalculate_release_delta_status(release2)

      {:ok, _} = delta |> Ecto.Changeset.change(status: :completed) |> Repo.update()
      assert {:ok, %{delta_status: :ready}} = ManagedDeployments.recalculate_release_delta_status(release2)
    end

    test "a delta built for a required release brings that release out of preparing", context do
      %{deployment_group: deployment_group, release2: release2} = add_releases(context)
      _ = connected_device(context, deployment_group, context.fw1)

      delta = Fixtures.firmware_delta_fixture(context.fw1, context.fw2, %{status: :processing})
      assert {:ok, %{delta_status: :preparing}} = ManagedDeployments.recalculate_release_delta_status(release2)

      {:ok, _} = delta |> Ecto.Changeset.change(status: :completed) |> Repo.update()

      # The delta builder only knows the firmware it built for, which here belongs
      # to a required release rather than the current one
      assert {:ok, releases} = ManagedDeployments.recalculate_release_delta_statuses_by_firmware_id(context.fw2.id)
      assert [%{delta_status: :ready}] = Enum.filter(releases, &(&1.id == release2.id))
    end

    test "the group's delta status keeps to the current release", context do
      %{deployment_group: deployment_group, release2: release2, release3: release3} = add_releases(context)
      _ = connected_device(context, deployment_group, context.fw1)
      _ = connected_device(context, deployment_group, context.fw2)

      # The device on fw1 is headed for the required release and waits on this
      # delta, but the group is about the release every device ends up on
      _ = Fixtures.firmware_delta_fixture(context.fw1, context.fw2, %{status: :processing})
      assert {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses(deployment_group)
      assert Repo.reload(release2).delta_status == :preparing
      assert delta_status(deployment_group) == :ready

      delta = Fixtures.firmware_delta_fixture(context.fw2, context.fw3, %{status: :failed})
      assert {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses(deployment_group)
      assert Repo.reload(release3).delta_status == :failed
      assert delta_status(deployment_group) == :failed

      # The required release is still preparing, and still not the group's concern
      {:ok, _} = delta |> Ecto.Changeset.change(status: :completed) |> Repo.update()
      assert {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses(deployment_group)
      assert Repo.reload(release2).delta_status == :preparing
      assert delta_status(deployment_group) == :ready
    end

    test "keeps each release's delta status to itself", context do
      %{deployment_group: deployment_group, release2: release2, release3: release3} = add_releases(context)
      _ = connected_device(context, deployment_group, context.fw1)
      _ = connected_device(context, deployment_group, context.fw2)

      _ = Fixtures.firmware_delta_fixture(context.fw1, context.fw2, %{status: :completed})
      building = Fixtures.firmware_delta_fixture(context.fw2, context.fw3, %{status: :processing})

      assert {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses(deployment_group)
      assert Repo.reload(release2).delta_status == :ready
      assert Repo.reload(release3).delta_status == :preparing
      assert delta_status(deployment_group) == :preparing

      {:ok, _} = building |> Ecto.Changeset.change(status: :failed) |> Repo.update()
      assert {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses(deployment_group)
      assert Repo.reload(release2).delta_status == :ready
      assert Repo.reload(release3).delta_status == :failed
      assert delta_status(deployment_group) == :failed

      {:ok, _} = building |> Ecto.Changeset.change(status: :completed) |> Repo.update()
      assert {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses(deployment_group)
      assert delta_status(deployment_group) == :ready
    end

    test "holds back only the devices headed for a release whose deltas aren't ready", context do
      %{deployment_group: deployment_group, release2: release2} = add_releases(context)

      %{id: behind_id} = connected_device(context, deployment_group, context.fw1)
      %{id: on_required_id} = connected_device(context, deployment_group, context.fw2)

      assert deployment_group |> Updates.available_for_update(10) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([behind_id, on_required_id])

      {:ok, _} = release2 |> Ecto.Changeset.change(delta_status: :preparing) |> Repo.update()

      # Only the device headed for release 2 waits; the one already on it carries
      # on to the current release
      assert [%{id: ^on_required_id}] = Updates.available_for_update(deployment_group, 10)
    end

    test "asks for deltas to the firmware each device is headed for", context do
      %{deployment_group: deployment_group} = add_releases(context)
      _ = connected_device(context, deployment_group, context.fw1)
      _ = connected_device(context, deployment_group, context.fw2)
      _ = connected_device(context, deployment_group, context.fw3)

      assert deployment_group.id
             |> Deployments.get_device_firmware_for_delta_generation_by_deployment_group()
             |> Enum.sort() ==
               Enum.sort([{context.fw1.id, context.fw2.id}, {context.fw2.id, context.fw3.id}])
    end
  end

  describe "set_deployment_release_required/3" do
    test "goes through even when the deltas it asks for can't be queued", context do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(context.deployment_group, %{delta_updatable: true}, context.user)

      %{deployment_group: deployment_group, release2: release2} =
        add_releases(%{context | deployment_group: deployment_group}, [])

      _ = connected_device(context, deployment_group, context.fw1)

      stub(Firmwares, :attempt_firmware_delta, fn _source, _target, _recalculate ->
        {:error, :failed_to_insert_delta}
      end)

      assert {:ok, release2} = ManagedDeployments.set_deployment_release_required(release2, true, context.user)
      assert release2.required
    end

    test "changes where devices are sent, and audits it", context do
      %{deployment_group: deployment_group, release2: release2, release3: release3} = add_releases(context, [])
      device = connected_device(context, deployment_group, context.fw1)

      :ok = NervesHub.PubSub |> Phoenix.PubSub.subscribe("deployment:#{deployment_group.id}")

      assert {:ok, release2} = ManagedDeployments.set_deployment_release_required(release2, true, context.user)
      assert release2.required
      assert ManagedDeployments.target_release(deployment_group, device).id == release2.id
      assert_receive %Broadcast{event: "deployments/update"}

      assert [audit_log | _] = AuditLogs.logs_for(deployment_group)
      assert audit_log.description =~ "marked release 2 as required"

      assert {:ok, release2} = ManagedDeployments.set_deployment_release_required(release2, false, context.user)
      refute Repo.reload(release2).required
      assert ManagedDeployments.target_release(deployment_group, device).id == release3.id
    end
  end

  describe "the penalty box" do
    setup context do
      %{deployment_group: deployment_group} = add_releases(context)
      device = connected_device(context, deployment_group, context.fw1)

      now = DateTime.utc_now(:second)
      device = device |> Ecto.Changeset.change(update_attempts: [now, now, now]) |> Repo.update!()

      %{deployment_group: deployment_group, device: device}
    end

    test "names the required release's firmware when a device is blocked", context do
      %{deployment_group: deployment_group, device: device} = context

      assert {:error, :updates_blocked, _device} = Updates.verify_update_eligibility(device, deployment_group)

      assert [audit_log | _] = AuditLogs.logs_for(device)
      assert audit_log.description =~ "Device failure rate met for firmware #{context.fw2.uuid}"
    end

    test "names the required release's firmware when the orchestrator blocks a device", context do
      %{deployment_group: deployment_group, device: device} = context

      assert {:ok, _device} = Updates.update_blocked_until(device, deployment_group)

      assert [audit_log | _] = AuditLogs.logs_for(device)
      assert audit_log.description =~ "Device failure rate met for firmware #{context.fw2.uuid}"
    end
  end

  describe "a workflow" do
    @canary %{
      "version" => 1,
      "steps" => [
        %{
          "name" => "Canary",
          "matching_conditions" => %{"tags" => ["canary"]},
          "concurrent_updates" => 10
        }
      ]
    }

    setup context do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          context.deployment_group,
          %{workflow_definition: @canary},
          context.user
        )

      releases = add_releases(%{context | deployment_group: deployment_group})
      [canary_step, catch_all_step] = Workflows.release_steps(releases.release3.id)

      Map.merge(releases, %{canary_step: canary_step, catch_all_step: catch_all_step})
    end

    defp step_device_ids(deployment_group, step) do
      deployment_group
      |> Workflows.step_devices_query(step)
      |> select([device: d], d.id)
      |> Repo.all()
    end

    defp on_firmware(device, firmware) do
      {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)
      {:ok, device} = Devices.update_firmware_metadata(device, metadata, :validated, false)
      device
    end

    test "leaves a device with a required release to take to the catch_all", context do
      %{deployment_group: deployment_group, canary_step: canary_step} = context

      ready = connected_device(context, deployment_group, context.fw2, %{tags: ["canary"]})
      behind = connected_device(context, deployment_group, context.fw1, %{tags: ["canary"]})

      ready_topic = "device:#{ready.id}"
      behind_topic = "device:#{behind.id}"
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, ready_topic)
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, behind_topic)

      # The canary stage takes only the device that can go straight to the current release
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert step_device_ids(deployment_group, canary_step) == [ready.id]
      assert_receive %Broadcast{topic: ^ready_topic, event: "update", payload: %{firmware_meta: %{uuid: uuid}}}
      assert uuid == context.fw3.uuid
      refute_receive %Broadcast{topic: ^behind_topic, event: "update"}, 100

      # ...and doesn't wait for the other once the canary is done
      FirmwareUpdates.clear_inflight_update(ready)
      _ = on_firmware(ready, context.fw3)

      assert WorkflowCoordinator.schedule_updates(deployment_group)
      assert Repo.reload(canary_step).status == :completed

      # The catch_all sends it the required release first
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert Repo.reload(context.catch_all_step).status == :in_progress
      assert_receive %Broadcast{topic: ^behind_topic, event: "update", payload: %{firmware_meta: %{uuid: uuid}}}
      assert uuid == context.fw2.uuid
    end

    test "stops updating or waiting for a device claimed before its release was marked required", context do
      %{deployment_group: deployment_group, canary_step: canary_step, release2: release2} = context

      {:ok, release2} = ManagedDeployments.set_deployment_release_required(release2, false, context.user)

      device = connected_device(context, deployment_group, context.fw1, %{tags: ["canary"]})

      assert Workflows.claim_devices(deployment_group, canary_step) == 1
      assert Workflows.claimed_device_count(deployment_group, canary_step) == 1
      assert [_] = Updates.available_for_workflow_step(deployment_group, canary_step, 10)
      refute Workflows.step_complete?(deployment_group, canary_step)

      {:ok, _} = ManagedDeployments.set_deployment_release_required(release2, true, context.user)

      assert step_device_ids(deployment_group, canary_step) == [device.id]
      assert Updates.available_for_workflow_step(deployment_group, canary_step, 10) == []
      assert Workflows.step_complete?(deployment_group, canary_step)

      # The step neither updates nor waits for it, so it doesn't fill the step's
      # match limit or count towards its failure tolerance either
      assert Workflows.claimed_device_count(deployment_group, canary_step) == 0
    end
  end
end
