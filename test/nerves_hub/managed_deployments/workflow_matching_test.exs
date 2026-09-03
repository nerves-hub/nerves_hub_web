defmodule NervesHub.ManagedDeployments.WorkflowMatchingTest do
  use NervesHub.DataCase, async: false

  import Ecto.Query

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Updates
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  @canary_then_everyone %{
    "version" => 1,
    "steps" => [
      %{
        "name" => "Canary",
        "matching_conditions" => %{"tags" => ["canary"], "match_limit" => 2},
        "concurrent_updates" => 10
      }
    ]
  }

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

  # Connected by default: a step only claims devices it could update now, so an
  # unconnected one is not a candidate.
  defp add_device(context, params, network_interface \\ :ethernet) do
    %{org: org, product: product, firmware: firmware, deployment_group: deployment_group} = context

    device = Fixtures.device_fixture(org, product, firmware, Map.put(params, :deployment_id, deployment_group.id))

    _ = connect(device, network_interface)

    device
  end

  defp add_disconnected_device(context, params) do
    %{org: org, product: product, firmware: firmware, deployment_group: deployment_group} = context

    Fixtures.device_fixture(org, product, firmware, Map.put(params, :deployment_id, deployment_group.id))
  end

  defp connect(device, network_interface \\ :ethernet) do
    {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
    :ok = Connections.device_connected(connection.id)

    connection
    |> Ecto.Changeset.change(%{network_interface: network_interface})
    |> Repo.update!()
  end

  defp steps(release), do: Workflows.release_steps(release.id)

  describe "claim_devices/2" do
    test "claims only devices carrying every tag the step asks for", context do
      canary = add_device(context, %{tags: ["canary", "nz"]})
      _partial = add_device(context, %{tags: ["nz"]})
      _untagged = add_device(context, %{tags: []})

      definition = %{
        "version" => 1,
        "steps" => [%{"name" => "Canary", "matching_conditions" => %{"tags" => ["canary", "nz"]}}]
      }

      %{release: release, deployment_group: deployment_group} = release_with(context, definition)
      [step | _] = steps(release)

      assert Workflows.claim_devices(deployment_group, step) == 1
      assert claimed_device_ids(step) == [canary.id]
    end

    test "claims by network interface", context do
      on_cellular = add_device(context, %{tags: ["canary"]}, :cellular)
      _on_wifi = add_device(context, %{tags: ["canary"]}, :wifi)

      definition = %{
        "version" => 1,
        "steps" => [
          %{"name" => "Cellular", "matching_conditions" => %{"network_interfaces" => ["cellular"]}}
        ]
      }

      %{release: release, deployment_group: deployment_group} = release_with(context, definition)
      [step | _] = steps(release)

      assert Workflows.claim_devices(deployment_group, step) == 1
      assert claimed_device_ids(step) == [on_cellular.id]
    end

    # A step's match limit is how many devices it updates, so a slot should not
    # go to one that cannot take the update. It stays unclaimed for a later pass,
    # or for the catch_all once this step has finished.
    test "passes over a device that is disconnected", context do
      _offline = add_disconnected_device(context, %{tags: ["canary"]})
      online = add_device(context, %{tags: ["canary"]})

      definition = %{
        "version" => 1,
        "steps" => [%{"name" => "Canary", "matching_conditions" => %{"tags" => ["canary"]}}]
      }

      %{release: release, deployment_group: deployment_group} = release_with(context, definition)
      [step | _] = steps(release)

      assert Workflows.claim_devices(deployment_group, step) == 1
      assert claimed_device_ids(step) == [online.id]
    end

    test "passes over a device in the penalty box", context do
      boxed = add_device(context, %{tags: ["canary"]})
      online = add_device(context, %{tags: ["canary"]})

      boxed
      |> Ecto.Changeset.change(%{
        updates_blocked_until: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      definition = %{
        "version" => 1,
        "steps" => [%{"name" => "Canary", "matching_conditions" => %{"tags" => ["canary"]}}]
      }

      %{release: release, deployment_group: deployment_group} = release_with(context, definition)
      [step | _] = steps(release)

      assert Workflows.claim_devices(deployment_group, step) == 1
      assert claimed_device_ids(step) == [online.id]
    end

    test "passes over a device already on the release's firmware", context do
      %{org_key: org_key, product: product} = context
      already_updated = add_device(context, %{tags: ["canary"]})
      online = add_device(context, %{tags: ["canary"]})

      next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "0.0.2"})
      {:ok, metadata} = NervesHub.Firmwares.metadata_from_firmware(next_firmware)
      {:ok, _} = NervesHub.Devices.update_firmware_metadata(already_updated, metadata, :validated, false)

      definition = %{
        "version" => 1,
        "steps" => [%{"name" => "Canary", "matching_conditions" => %{"tags" => ["canary"]}}]
      }

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          context.deployment_group,
          %{workflow_definition: definition},
          context.user
        )

      {:ok, {release, _}} =
        ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, context.user, %{},
          broadcast: false
        )

      {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group.id)
      [step | _] = steps(release)

      assert Workflows.claim_devices(deployment_group, step) == 1
      assert claimed_device_ids(step) == [online.id]
    end

    test "stops at the match limit and tops up later rather than re-picking", context do
      first = add_device(context, %{tags: ["canary"]})
      second = add_device(context, %{tags: ["canary"]})

      %{release: release, deployment_group: deployment_group} = release_with(context, @canary_then_everyone)
      [step | _] = steps(release)

      # match_limit is 2 and only these two match, so the step fills up.
      assert Workflows.claim_devices(deployment_group, step) == 2
      assert claimed_device_ids(step) == Enum.sort([first.id, second.id])

      # A third canary appears, but the step is full and its membership is fixed.
      _third = add_device(context, %{tags: ["canary"]})

      assert Workflows.claim_devices(deployment_group, step) == 0
      assert claimed_device_ids(step) == Enum.sort([first.id, second.id])
    end

    # The catch_all covers whatever is left rather than recording a claim on it,
    # so that a 400k-device deployment does not write 400k rows to say "everyone
    # else".
    test "the catch_all covers what earlier steps left, without claiming it", context do
      canary = add_device(context, %{tags: ["canary"]})
      other_one = add_device(context, %{tags: []})
      other_two = add_device(context, %{tags: []})

      definition = %{
        "version" => 1,
        "steps" => [%{"name" => "Canary", "matching_conditions" => %{"tags" => ["canary"], "match_limit" => 1}}]
      }

      %{release: release, deployment_group: deployment_group} = release_with(context, definition)
      [canary_step, catch_all] = steps(release)

      assert Workflows.claim_devices(deployment_group, canary_step) == 1
      assert Workflows.claim_devices(deployment_group, catch_all) == 0

      assert claimed_device_ids(canary_step) == [canary.id]
      assert claimed_device_ids(catch_all) == []

      assert covered_device_ids(deployment_group, catch_all) == Enum.sort([other_one.id, other_two.id])
    end

    test "an approval_required step claims nothing", context do
      _device = add_device(context, %{tags: ["canary"]})

      definition = %{"version" => 1, "steps" => [%{"name" => "Sign-off", "type" => "approval_required"}]}

      %{release: release, deployment_group: deployment_group} = release_with(context, definition)
      [approval | _] = steps(release)

      assert Workflows.claim_devices(deployment_group, approval) == 0
    end
  end

  describe "available_for_workflow_step/3" do
    test "offers only the step's own devices", context do
      claimed = add_device(context, %{tags: ["canary"]})
      unclaimed = add_device(context, %{tags: []})

      definition = %{
        "version" => 1,
        "steps" => [%{"name" => "Canary", "matching_conditions" => %{"tags" => ["canary"]}}]
      }

      %{release: release, deployment_group: deployment_group} = release_with(context, definition)
      [step | _] = steps(release)

      _ = Workflows.claim_devices(deployment_group, step)

      assert [available] = Updates.available_for_workflow_step(deployment_group, step, 10)
      assert available.id == claimed.id

      # The unclaimed device is connected and out of date, so it would be offered
      # were the workflow not holding it back for a later step.
      assert unclaimed.id in Enum.map(Updates.available_for_update(deployment_group, 10), & &1.id)
    end
  end

  describe "step_complete?/2" do
    test "a step with no devices left out of date is done", context do
      %{release: release, deployment_group: deployment_group} = release_with(context, @canary_then_everyone)
      [step | _] = steps(release)

      assert Workflows.step_complete?(deployment_group, step)
    end

    test "a step waits for a claimed device that is still on old firmware", context do
      _canary = add_device(context, %{tags: ["canary"]})

      %{release: release, deployment_group: deployment_group} = release_with(context, @canary_then_everyone)
      [step | _] = steps(release)

      _ = Workflows.claim_devices(deployment_group, step)

      refute Workflows.step_complete?(deployment_group, step)
    end

    test "a catch_all is never complete, even with every device up to date", context do
      %{release: release, deployment_group: deployment_group} = release_with(context, @canary_then_everyone)
      [_canary, catch_all] = steps(release)

      refute Workflows.step_complete?(deployment_group, catch_all)
    end

    test "an approval_required step is complete once approved", context do
      %{user: user} = context
      definition = %{"version" => 1, "steps" => [%{"name" => "Sign-off", "type" => "approval_required"}]}

      %{release: release, deployment_group: deployment_group} = release_with(context, definition)
      [approval | _] = steps(release)

      refute Workflows.step_complete?(deployment_group, approval)

      approved = Workflows.approve_step(approval, user)

      assert approved.approved_by_id == user.id
      assert Workflows.step_complete?(deployment_group, approved)
    end
  end

  describe "skip_step/2" do
    test "releases the step's devices so a later step can take them", context do
      canary = add_device(context, %{tags: ["canary"]})

      %{release: release, deployment_group: deployment_group} = release_with(context, @canary_then_everyone)
      [canary_step, catch_all] = steps(release)

      assert Workflows.claim_devices(deployment_group, canary_step) == 1

      # While the canary step holds it, the catch_all does not cover it.
      assert covered_device_ids(deployment_group, catch_all) == []

      {:ok, skipped} = Workflows.skip_step(canary_step, context.user)

      assert skipped.status == :skipped
      assert claimed_device_ids(canary_step) == []
      assert covered_device_ids(deployment_group, catch_all) == [canary.id]
    end
  end

  describe "WorkflowCoordinator.schedule_updates/1" do
    test "starts the first step, claims its devices, and schedules them", context do
      canary = add_device(context, %{tags: ["canary"]})
      _other = add_device(context, %{tags: []})

      _ = connect(canary)

      %{release: release, deployment_group: deployment_group} = release_with(context, @canary_then_everyone)

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{canary.id}")

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      [canary_step, _catch_all] = steps(release)

      assert canary_step.status == :in_progress
      assert claimed_device_ids(canary_step) == [canary.id]
      assert_receive %Broadcast{event: "update"}, 1_000
    end

    test "does not schedule a device an earlier step is holding", context do
      canary = add_device(context, %{tags: ["canary"]})
      other = add_device(context, %{tags: []})

      _ = connect(canary)
      _ = connect(other)

      %{release: release, deployment_group: deployment_group} = release_with(context, @canary_then_everyone)

      other_topic = "device:#{other.id}"
      Phoenix.PubSub.subscribe(NervesHub.PubSub, other_topic)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      [_canary_step, catch_all] = steps(release)

      # The canary step is in progress and not done, so the catch_all has not
      # started and `other` is left alone.
      assert catch_all.status == :waiting
      refute_receive %Broadcast{topic: ^other_topic, event: "update"}, 500
    end

    test "moves to the next step once the current one has nothing outstanding", context do
      %{release: release, deployment_group: deployment_group} = release_with(context, @canary_then_everyone)

      # No canaries exist, so the canary step has nothing to wait for.
      assert WorkflowCoordinator.schedule_updates(deployment_group)

      [canary_step, catch_all] = steps(release)

      assert canary_step.status == :completed
      assert catch_all.status == :waiting

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      [_canary_step, catch_all] = steps(release)

      assert catch_all.status == :in_progress
    end
  end

  defp covered_device_ids(deployment_group, step) do
    deployment_group
    |> Workflows.step_devices_query(step)
    |> select([device: d], d.id)
    |> Repo.all()
    |> Enum.sort()
  end

  defp claimed_device_ids(step) do
    "deployment_workflow_steps_devices"
    |> where([sd], sd.deployment_workflow_step_id == ^step.id)
    |> select([sd], sd.device_id)
    |> Repo.all()
    |> Enum.sort()
  end
end
