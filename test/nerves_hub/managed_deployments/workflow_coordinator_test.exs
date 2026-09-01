defmodule NervesHub.ManagedDeployments.WorkflowCoordinatorTest do
  @moduledoc """
  How a workflow paces and walks itself, as opposed to how it decides which
  devices a step covers, which is `NervesHub.ManagedDeployments.WorkflowMatchingTest`.
  """

  use NervesHub.DataCase, async: false

  import Ecto.Query

  alias NervesHub.AuditLogs
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Firmwares
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep.FailureTolerance
  alias NervesHub.ManagedDeployments.Orchestrator
  alias NervesHub.ManagedDeployments.Orchestrator.DefaultCoordinator
  alias NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Products.Notification
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user, is_active: true})

    %{
      user: user,
      org: org,
      product: product,
      org_key: org_key,
      firmware: firmware,
      deployment_group: deployment_group
    }
  end

  defp release_with(context, definition) do
    %{deployment_group: deployment_group, user: user, org_key: org_key, product: product} = context

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: definition}, user)

    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "0.0.2"})

    {:ok, {release, _}} =
      ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{}, broadcast: false)

    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group.id)

    %{release: release, deployment_group: deployment_group, next_firmware: next_firmware}
  end

  defp add_device(context, params) do
    %{org: org, product: product, firmware: firmware, deployment_group: deployment_group} = context

    device = Fixtures.device_fixture(org, product, firmware, Map.put(params, :deployment_id, deployment_group.id))

    {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
    :ok = Connections.device_connected(connection.id)

    device
  end

  # Put a device on the release's firmware, which is what a step waits for.
  defp mark_updated(device, firmware) do
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)
    {:ok, device} = Devices.update_firmware_metadata(device, metadata, :validated, false)

    device
  end

  defp steps(release), do: Workflows.release_steps(release.id)

  defp covered_device_ids(deployment_group, step) do
    deployment_group
    |> Workflows.step_devices_query(step)
    |> select([device: d], d.id)
    |> Repo.all()
    |> Enum.sort()
  end

  defp product_notifications(product) do
    Notification
    |> where([n], n.product_id == ^product.id)
    |> Repo.all()
  end

  defp step(release, number), do: release |> steps() |> Enum.find(&(&1.number == number))

  describe "available_slots/1" do
    @two_at_a_time %{
      "version" => 1,
      "steps" => [
        %{
          "name" => "Canary",
          "matching_conditions" => %{"tags" => ["canary"]},
          "concurrent_updates" => 2
        }
      ]
    }

    test "starts at the step's own concurrency, not the deployment group's", context do
      %{release: release, deployment_group: deployment_group} = release_with(context, @two_at_a_time)
      canary = step(release, 1)

      # The group allows far more than the step does.
      assert deployment_group.concurrent_updates > 2
      assert Workflows.available_slots(deployment_group, canary) == 2
    end

    test "shrinks as the step's own devices go inflight", context do
      first = add_device(context, %{tags: ["canary"]})
      second = add_device(context, %{tags: ["canary"]})

      %{release: release, deployment_group: deployment_group} = release_with(context, @two_at_a_time)
      canary = step(release, 1)

      assert Workflows.claim_devices(deployment_group, canary) == 2
      assert Workflows.available_slots(deployment_group, canary) == 2

      {:ok, _} = DeviceEvents.schedule_update(first.id, deployment_group, priority_queue: false)
      assert Workflows.available_slots(deployment_group, canary) == 1

      {:ok, _} = DeviceEvents.schedule_update(second.id, deployment_group, priority_queue: false)
      assert Workflows.available_slots(deployment_group, canary) == 0
    end

    # Each step paces itself. A device updating under one step must not eat into
    # the slots of another.
    test "is not spent by devices belonging to a different step", context do
      canary_device = add_device(context, %{tags: ["canary"]})
      _other = add_device(context, %{tags: []})

      %{release: release, deployment_group: deployment_group} = release_with(context, @two_at_a_time)
      canary = step(release, 1)
      catch_all = step(release, 2)

      assert Workflows.claim_devices(deployment_group, canary) == 1

      {:ok, _} = DeviceEvents.schedule_update(canary_device.id, deployment_group, priority_queue: false)

      # The canary's own slot is spent, but a step that counts its claims is not
      # charged for a device belonging to another.
      assert Workflows.available_slots(deployment_group, canary) == 1
      refute Workflows.claimed_device_count(catch_all) == 1
    end

    test "never goes below zero", context do
      %{release: release, deployment_group: deployment_group} = release_with(context, @two_at_a_time)
      canary = step(release, 1)

      for _ <- 1..3 do
        device = add_device(context, %{tags: ["canary"]})
        _ = Workflows.claim_devices(deployment_group, canary)
        {:ok, _} = DeviceEvents.schedule_update(device.id, deployment_group, priority_queue: false)
      end

      assert FirmwareUpdates.count_inflight_updates_for_workflow_step(canary) > canary.concurrency
      assert Workflows.available_slots(deployment_group, canary) == 0
    end
  end

  describe "pacing a step" do
    test "schedules no more than the step's concurrency in one pass", context do
      devices = for _ <- 1..5, do: add_device(context, %{tags: ["canary"]})

      %{deployment_group: deployment_group, release: release} = release_with(context, @two_at_a_time)

      for device <- devices, do: Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      canary = step(release, 1)

      # All five are covered by the step, but only two are told to update.
      assert Workflows.claimed_device_count(canary) == 5
      assert FirmwareUpdates.count_inflight_updates_for_workflow_step(canary) == 2

      # A second pass adds nothing while those two are still going.
      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      assert FirmwareUpdates.count_inflight_updates_for_workflow_step(canary) == 2
    end

    test "picks up where it left off once a slot frees", context do
      devices = for _ <- 1..3, do: add_device(context, %{tags: ["canary"]})

      %{deployment_group: deployment_group, release: release, next_firmware: next_firmware} =
        release_with(context, @two_at_a_time)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      canary = step(release, 1)
      assert FirmwareUpdates.count_inflight_updates_for_workflow_step(canary) == 2

      # One finishes: its inflight record goes and it reports the new firmware.
      [finished | _] = devices
      FirmwareUpdates.clear_inflight_update(finished)
      _ = mark_updated(finished, next_firmware)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert FirmwareUpdates.count_inflight_updates_for_workflow_step(step(release, 1)) == 2
    end
  end

  describe "walking a workflow" do
    @canary_then_rest %{
      "version" => 1,
      "steps" => [
        %{
          "name" => "Canary",
          "matching_conditions" => %{"tags" => ["canary"]},
          "concurrent_updates" => 10
        }
      ]
    }

    test "a device only updates once its step is the active one", context do
      canary_device = add_device(context, %{tags: ["canary"]})
      later_device = add_device(context, %{tags: []})

      %{deployment_group: deployment_group, release: release, next_firmware: next_firmware} =
        release_with(context, @canary_then_rest)

      canary_topic = "device:#{canary_device.id}"
      later_topic = "device:#{later_device.id}"
      Phoenix.PubSub.subscribe(NervesHub.PubSub, canary_topic)
      Phoenix.PubSub.subscribe(NervesHub.PubSub, later_topic)

      # First pass: the canary step is active, so only the canary is told to update.
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert_receive %Broadcast{topic: ^canary_topic, event: "update"}, 1_000
      refute_receive %Broadcast{topic: ^later_topic, event: "update"}, 200

      assert step(release, 1).status == :in_progress
      assert step(release, 2).status == :waiting

      # The canary lands on the new firmware.
      FirmwareUpdates.clear_inflight_update(canary_device)
      _ = mark_updated(canary_device, next_firmware)

      # Second pass: the canary step is done, so it completes and hands over.
      assert WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 1).status == :completed
      assert step(release, 1).finished_at

      # Third pass: the catch_all starts, claims what is left, and updates it.
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      catch_all = step(release, 2)
      assert catch_all.status == :in_progress
      assert_receive %Broadcast{topic: ^later_topic, event: "update"}, 1_000
    end

    test "the catch_all keeps running rather than completing", context do
      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_then_rest)

      # No canaries, so the first step completes immediately and the catch_all starts.
      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 2).status == :in_progress

      # Nothing is outstanding, but a catch_all is the release's steady state.
      for _ <- 1..3, do: WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 2).status == :in_progress
      refute step(release, 2).finished_at
    end

    # The orchestrator holds a deployment group for the life of the release, so
    # the steps preloaded on it are a snapshot from before any of this ran.
    test "reads step statuses back rather than trusting the preloaded copy", context do
      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_then_rest)

      # Every step on this copy still says :waiting, and stays saying so.
      assert Enum.all?(deployment_group.current_release.steps, &(&1.status == :waiting))

      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert Enum.all?(deployment_group.current_release.steps, &(&1.status == :waiting))

      # The stale copy did not stop it starting the first step and moving on.
      assert step(release, 1).status == :completed
      assert step(release, 2).status == :in_progress
    end

    test "claiming again after a restart does not duplicate a step's devices", context do
      _canary = add_device(context, %{tags: ["canary"]})

      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_then_rest)
      canary = step(release, 1)

      assert Workflows.claim_devices(deployment_group, canary) == 1
      assert Workflows.claim_devices(deployment_group, canary) == 0
      assert Workflows.claimed_device_count(canary) == 1
    end
  end

  describe "what a release records" do
    # The reason a catch_all derives its devices rather than claiming them: on a
    # deployment of 400k devices, recording "everyone else" would be 400k rows per
    # release to write, keep, and later migrate — to say something the other
    # steps' claims already say.
    test "only the staged devices are recorded, not every device", context do
      canary = add_device(context, %{tags: ["canary"]})
      others = for _ <- 1..4, do: add_device(context, %{tags: []})

      %{deployment_group: deployment_group, release: release, next_firmware: next_firmware} =
        release_with(context, @canary_then_rest)

      # Walk the whole workflow: canary, then the catch_all.
      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      FirmwareUpdates.clear_inflight_update(canary)
      _ = mark_updated(canary, next_firmware)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 2).status == :in_progress

      recorded =
        "deployment_workflow_steps_devices"
        |> select([sd], sd.device_id)
        |> Repo.all()

      assert recorded == [canary.id]

      # The others are covered and scheduled all the same.
      assert covered_device_ids(deployment_group, step(release, 2)) == others |> Enum.map(& &1.id) |> Enum.sort()
    end
  end

  describe "an approval step" do
    @needs_approval %{
      "version" => 1,
      "steps" => [
        %{"name" => "Sign-off", "type" => "approval_required"}
      ]
    }

    test "holds everything until somebody approves it", context do
      device = add_device(context, %{tags: []})

      %{deployment_group: deployment_group, release: release} = release_with(context, @needs_approval)

      topic = "device:#{device.id}"
      Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)

      refute WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 1).status == :in_progress
      assert step(release, 2).status == :waiting
      refute_receive %Broadcast{topic: ^topic, event: "update"}, 200

      # Running again changes nothing while it waits.
      refute WorkflowCoordinator.schedule_updates(deployment_group)
      assert step(release, 1).status == :in_progress

      _ = Workflows.approve_step(step(release, 1), context.user)

      assert WorkflowCoordinator.schedule_updates(deployment_group)
      assert step(release, 1).status == :completed

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 2).status == :in_progress
      assert_receive %Broadcast{topic: ^topic, event: "update"}, 1_000
    end
  end

  describe "a step that cannot finish on its own" do
    @canary_step %{
      "version" => 1,
      "steps" => [%{"name" => "Canary", "matching_conditions" => %{"tags" => ["canary"]}}]
    }

    test "a deleted device does not hold a step open forever", context do
      canary_device = add_device(context, %{tags: ["canary"]})

      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_step)
      canary = step(release, 1)

      assert Workflows.claim_devices(deployment_group, canary) == 1
      refute Workflows.step_complete?(deployment_group, canary)

      canary_device
      |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(:second)})
      |> Repo.update!()

      assert Workflows.step_complete?(deployment_group, canary)
    end

    # A canary that never comes back would otherwise hold the workflow where it is.
    test "skipping hands its devices to the next step and lets the workflow move on", context do
      canary_device = add_device(context, %{tags: ["canary"]})

      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_step)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      canary = step(release, 1)
      assert canary.status == :in_progress
      refute Workflows.step_complete?(deployment_group, canary)

      {:ok, _} = Workflows.skip_step(canary, context.user)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      catch_all = step(release, 2)
      assert catch_all.status == :in_progress
      assert Workflows.claimed_device_count(step(release, 1)) == 0
      assert covered_device_ids(deployment_group, catch_all) == [canary_device.id]

      topic = "device:#{canary_device.id}"
      Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)
    end
  end

  describe "failing a step" do
    @strict %{
      "version" => 1,
      "steps" => [
        %{
          "name" => "Canary",
          "matching_conditions" => %{"tags" => ["canary"]},
          "failure_tolerance" => %{"devices" => 2}
        }
      ]
    }

    # A device counts as failed once it is in the penalty box, which is where
    # repeated failed update attempts put it.
    defp fail_device(device) do
      device
      |> Ecto.Changeset.change(%{updates_blocked_until: DateTime.utc_now(:second) |> DateTime.add(3600, :second)})
      |> Repo.update!()
    end

    test "a step fails once its tolerance is used up, and holds the workflow there", context do
      first = add_device(context, %{tags: ["canary"]})
      second = add_device(context, %{tags: ["canary"]})
      later = add_device(context, %{tags: []})

      %{deployment_group: deployment_group, release: release} = release_with(context, @strict)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      canary = step(release, 1)
      assert canary.status == :in_progress

      # One failure is within tolerance.
      _ = fail_device(first)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      assert step(release, 1).status == :in_progress

      # The second uses it up.
      _ = fail_device(second)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      failed = step(release, 1)
      assert failed.status == :error
      assert failed.finished_at

      # The workflow stops there rather than stepping over it.
      later_topic = "device:#{later.id}"
      Phoenix.PubSub.subscribe(NervesHub.PubSub, later_topic)

      refute WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 2).status == :waiting
      refute_receive %Broadcast{topic: ^later_topic, event: "update"}, 200
    end

    test "a percentage tolerance is of the devices the step claimed", context do
      devices = for _ <- 1..4, do: add_device(context, %{tags: ["canary"]})

      definition = %{
        "version" => 1,
        "steps" => [
          %{
            "name" => "Canary",
            "matching_conditions" => %{"tags" => ["canary"]},
            "failure_tolerance" => %{"percent" => 50}
          }
        ]
      }

      %{deployment_group: deployment_group, release: release} = release_with(context, definition)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      canary = step(release, 1)
      assert Workflows.claimed_device_count(canary) == 4
      assert Workflows.failure_limit(canary, 4) == 2

      [first, second | _] = devices

      _ = fail_device(first)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      assert step(release, 1).status == :in_progress

      _ = fail_device(second)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      assert step(release, 1).status == :error
    end

    # Rounding down would turn a small percentage into "no failures allowed",
    # which is not what asking for a percentage means.
    test "a percentage never rounds down to nothing", context do
      %{release: release} = release_with(context, @strict)
      canary = step(release, 1)

      tolerance = %FailureTolerance{percent: 5}

      assert Workflows.failure_limit(%{canary | failure_tolerance: tolerance}, 10) == 1
      assert Workflows.failure_limit(%{canary | failure_tolerance: tolerance}, 100) == 5
    end

    test "a catch_all never fails, however many of its devices do", context do
      device = add_device(context, %{tags: []})

      %{deployment_group: deployment_group, release: release} = release_with(context, @strict)

      # Get past the canary step, which has no devices.
      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      catch_all = step(release, 2)
      assert catch_all.status == :in_progress
      assert Workflows.failure_limit(catch_all, 1) == :never

      _ = fail_device(device)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 2).status == :in_progress
      refute Workflows.step_failed?(deployment_group, catch_all)
    end

    test "an update_devices step defaults to failing on the first device", context do
      %{release: release} = release_with(context, @canary_then_rest)

      assert Workflows.failure_limit(step(release, 1), 10) == 1
    end
  end

  describe "announcing that a workflow has stopped" do
    test "a failed step is measured, recorded, and raised to the product", context do
      canary_device = add_device(context, %{tags: ["canary"]})

      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_then_rest)

      :telemetry_test.attach_event_handlers(self(), [[:nerves_hub, :deployments, :workflow, :halted]])

      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      _ = fail_device(canary_device)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 1).status == :error

      assert_receive {[:nerves_hub, :deployments, :workflow, :halted], _ref, %{count: 1},
                      %{reason: :failed, step_number: 1}}

      assert Enum.any?(
               AuditLogs.logs_for(deployment_group),
               &(&1.description =~ "failed for deployment group" and &1.actor_type == DeploymentGroup)
             )

      assert [notification] = product_notifications(context.product)
      assert notification.level == :error
      assert notification.title =~ "stopped after devices failed"
      assert notification.message =~ deployment_group.name
    end

    test "reaching an approval step is announced too", context do
      definition = %{
        "version" => 1,
        "steps" => [%{"name" => "Sign-off", "type" => "approval_required"}]
      }

      %{deployment_group: deployment_group, release: release} = release_with(context, definition)

      :telemetry_test.attach_event_handlers(self(), [[:nerves_hub, :deployments, :workflow, :halted]])

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 1).status == :in_progress

      assert_receive {[:nerves_hub, :deployments, :workflow, :halted], _ref, %{count: 1}, %{reason: :awaiting_approval}}

      assert [notification] = product_notifications(context.product)
      assert notification.level == :info
      assert notification.title =~ "waiting for approval"
    end

    # The orchestrator runs every few seconds while a workflow is stopped; saying
    # so once per pass would bury everything else.
    test "a workflow that stays stopped is not announced over and over", context do
      canary_device = add_device(context, %{tags: ["canary"]})

      %{deployment_group: deployment_group} = release_with(context, @canary_then_rest)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      _ = fail_device(canary_device)

      for _ <- 1..4, do: WorkflowCoordinator.schedule_updates(deployment_group)

      assert [notification] = product_notifications(context.product)
      assert notification.occurrence_count == 1
    end
  end

  describe "retrying a failed step" do
    test "lets its devices out of the penalty box and starts it again", context do
      canary_device = add_device(context, %{tags: ["canary"]})

      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_then_rest)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      canary_device
      |> Ecto.Changeset.change(%{
        updates_blocked_until: DateTime.utc_now(:second) |> DateTime.add(3600, :second),
        update_attempts: [DateTime.utc_now(:second)]
      })
      |> Repo.update!()

      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      assert step(release, 1).status == :error

      assert {:ok, retried} = Workflows.retry_step(deployment_group, step(release, 1), context.user)

      assert retried.status == :in_progress
      refute retried.finished_at

      released = Repo.reload(canary_device)
      refute released.updates_blocked_until
      assert released.update_attempts == []

      # It still holds its devices, so the workflow carries on where it stopped.
      assert Workflows.claimed_device_count(step(release, 1)) == 1
    end

    test "a step that has not failed cannot be retried", context do
      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_then_rest)

      assert {:error, :not_retryable} = Workflows.retry_step(deployment_group, step(release, 1), context.user)
    end
  end

  describe "skipping" do
    test "the trailing catch_all cannot be skipped", context do
      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_then_rest)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      catch_all = step(release, 2)
      assert catch_all.status == :in_progress

      refute Workflows.skippable?(catch_all)
      assert {:error, :not_skippable} = Workflows.skip_step(catch_all, context.user)
    end

    test "a failed step can be skipped, and the workflow moves on", context do
      canary_device = add_device(context, %{tags: ["canary"]})

      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_then_rest)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      _ = fail_device(canary_device)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 1).status == :error

      assert {:ok, _} = Workflows.skip_step(step(release, 1), context.user)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 2).status == :in_progress
      assert covered_device_ids(deployment_group, step(release, 2)) == [canary_device.id]
    end

    test "a completed step has nothing to skip", context do
      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_then_rest)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert step(release, 1).status == :completed
      refute Workflows.skippable?(step(release, 1))
    end
  end

  describe "a device that leaves the deployment group" do
    # It is no longer this step's business, and counting it would hold the step
    # open for a device that is never going to take this release.
    test "stops holding its step open", context do
      canary_device = add_device(context, %{tags: ["canary"]})

      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_then_rest)
      canary = step(release, 1)

      assert Workflows.claim_devices(deployment_group, canary) == 1
      refute Workflows.step_complete?(deployment_group, canary)

      canary_device
      |> Ecto.Changeset.change(%{deployment_id: nil})
      |> Repo.update!()

      assert Workflows.step_complete?(deployment_group, canary)
    end
  end

  describe "the orchestrator process" do
    @canary_step %{
      "version" => 1,
      "steps" => [%{"name" => "Canary", "matching_conditions" => %{"tags" => ["canary"]}}]
    }

    test "runs a workflow when the release has steps", context do
      canary_device = add_device(context, %{tags: ["canary"]})

      %{deployment_group: deployment_group, release: release} = release_with(context, @canary_step)

      topic = "device:#{canary_device.id}"
      Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)

      {:ok, pid} =
        start_supervised(%{
          id: "Orchestrator##{deployment_group.id}",
          start: {Orchestrator, :start_link, [deployment_group, false]},
          restart: :temporary
        })

      state = :sys.get_state(pid)

      assert state.coordinator == WorkflowCoordinator

      assert_receive %Broadcast{topic: ^topic, event: "update"}, 2_000
      assert step(release, 1).status == :in_progress
      assert Workflows.claimed_device_count(step(release, 1)) == 1
    end

    test "uses the default coordinator when the release has no steps", %{deployment_group: deployment_group} do
      {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group.id)

      {:ok, pid} =
        start_supervised(%{
          id: "Orchestrator##{deployment_group.id}",
          start: {Orchestrator, :start_link, [deployment_group, false]},
          restart: :temporary
        })

      state = :sys.get_state(pid)

      assert state.coordinator == DefaultCoordinator
    end
  end
end
