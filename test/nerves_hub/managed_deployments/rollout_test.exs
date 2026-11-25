defmodule NervesHub.ManagedDeployments.RolloutTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Rollout
  alias NervesHub.Repo

  @definition %{
    "version" => 1,
    "steps" => [
      %{"name" => "Canary", "matching_conditions" => %{"tags" => ["canary"], "match_limit" => 5}},
      %{"name" => "Sign-off", "type" => "approval_required"}
    ]
  }

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    old_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0"})
    deployment_group = Fixtures.deployment_group_fixture(old_firmware, %{user: user, is_active: true})

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.1.0"})

    {:ok, {_release, deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, new_firmware, nil, user, %{}, broadcast: false)

    %{
      user: user,
      org: org,
      product: product,
      org_key: org_key,
      old_firmware: old_firmware,
      new_firmware: new_firmware,
      deployment_group: reload(deployment_group, product)
    }
  end

  defp reload(deployment_group, product) do
    ManagedDeployments.get_by_product_and_name!(product, deployment_group.name, true)
  end

  defp device(context, firmware, attrs \\ %{}) do
    %{org: org, product: product, deployment_group: deployment_group} = context
    {changes, attrs} = Map.split(attrs, [:update_mode, :updates_blocked_until, :consecutive_failed_updates])

    org
    |> Fixtures.device_fixture(product, firmware, Map.put(attrs, :deployment_id, deployment_group.id))
    |> Ecto.Changeset.change(changes)
    |> Repo.update!()
  end

  defp in_an_hour(), do: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

  describe "counts/1" do
    test "puts every device in exactly one state", context do
      %{deployment_group: deployment_group, old_firmware: old, new_firmware: new} = context

      device(context, new)
      device(context, new, %{update_mode: :off})
      device(context, old, %{update_mode: :off})
      device(context, old, %{updates_blocked_until: in_an_hour(), consecutive_failed_updates: 3})
      device(context, old, %{consecutive_failed_updates: 1})
      updating = device(context, old)
      {:ok, _} = Fixtures.inflight_update(updating, deployment_group)
      device(context, old)

      assert %{
               deployment_group.id => %{
                 total: 7,
                 updated: 2,
                 updates_off: 1,
                 updating: 1,
                 penalty_box: 1,
                 failed: 1,
                 waiting: 1
               }
             } == Rollout.counts([deployment_group])
    end

    test "leaves out deleted devices and gives a group with none empty counts", context do
      %{deployment_group: deployment_group, old_firmware: old} = context

      context
      |> device(old)
      |> Ecto.Changeset.change(deleted_at: DateTime.truncate(DateTime.utc_now(), :second))
      |> Repo.update!()

      assert Rollout.counts([deployment_group]) == %{deployment_group.id => Rollout.empty_counts()}
    end
  end

  describe "step_counts/1" do
    setup context do
      %{deployment_group: deployment_group, user: user, new_firmware: new} = context

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: @definition}, user)

      newer = Fixtures.firmware_fixture(context.org_key, context.product, %{version: "1.2.0"})

      {:ok, {_release, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, newer, nil, user, %{}, broadcast: false)

      %{deployment_group: reload(deployment_group, context.product), newer_firmware: newer, previous_firmware: new}
    end

    test "counts a step's claimed devices, and the rest under the catch-all", context do
      %{deployment_group: deployment_group, newer_firmware: newer, old_firmware: old} = context

      canary_updated = device(context, newer, %{tags: ["canary"]})
      canary_failed = device(context, old, %{tags: ["canary"], updates_blocked_until: in_an_hour()})
      device(context, old)
      device(context, newer)

      [canary, sign_off, catch_all] = Enum.sort_by(deployment_group.current_release.steps, & &1.number)

      for device <- [canary_updated, canary_failed] do
        Repo.insert_all("deployment_workflow_steps_devices", [
          %{
            deployment_workflow_step_id: canary.id,
            device_id: device.id,
            inserted_at: NaiveDateTime.utc_now(:second),
            updated_at: NaiveDateTime.utc_now(:second)
          }
        ])
      end

      counts = Rollout.step_counts([deployment_group])

      assert counts[canary.id] == %{devices: 2, updated: 1, failed: 1}
      assert counts[sign_off.id] == %{devices: 0, updated: 0, failed: 0}
      assert counts[catch_all.id] == %{devices: 2, updated: 1, failed: 0}
    end
  end

  describe "unreached/2" do
    test "lists devices held back, the penalty box first, and counts them all", context do
      %{deployment_group: deployment_group, old_firmware: old, new_firmware: new} = context

      device(context, new, %{consecutive_failed_updates: 2})
      off = device(context, old, %{update_mode: :off, identifier: "a-off"})
      failed = device(context, old, %{consecutive_failed_updates: 1, identifier: "b-failed"})
      boxed = device(context, old, %{updates_blocked_until: in_an_hour(), identifier: "c-boxed"})
      device(context, old)

      {rows, total} = Rollout.unreached(deployment_group, 2)

      assert total == 3

      assert [
               %{device: %Device{id: boxed_id}, state: :penalty_box},
               %{device: %Device{id: failed_id}, state: :failed}
             ] = rows

      assert boxed_id == boxed.id
      assert failed_id == failed.id

      {rows, 3} = Rollout.unreached(deployment_group, 10)
      assert %{state: :updates_off} = Enum.find(rows, &(&1.device.id == off.id))
    end
  end

  describe "waiting on a failed delta" do
    setup context do
      %{deployment_group: deployment_group, new_firmware: new, product: product} = context

      Repo.update!(Ecto.Changeset.change(deployment_group, delta_updatable: true))
      new = Repo.update!(Ecto.Changeset.change(new, delta_updatable: true))

      %{deployment_group: reload(deployment_group, product), new_firmware: new}
    end

    test "is listed after the penalty box with the version its delta was from, and counted by version", context do
      %{deployment_group: deployment_group, old_firmware: old, new_firmware: new} = context

      older = Fixtures.firmware_fixture(context.org_key, context.product, %{version: "0.9.0"})
      building = Fixtures.firmware_fixture(context.org_key, context.product, %{version: "0.8.0"})

      Fixtures.firmware_delta_fixture(old, new, %{status: :failed})
      Fixtures.firmware_delta_fixture(older, new, %{status: :timed_out})
      Fixtures.firmware_delta_fixture(building, new, %{status: :processing})

      waiting = device(context, old, %{identifier: "b-waiting", consecutive_failed_updates: 1})
      device(context, old, %{identifier: "c-waiting"})
      device(context, older, %{identifier: "d-waiting"})
      boxed = device(context, old, %{identifier: "a-boxed", updates_blocked_until: in_an_hour()})
      # It asks for its own updates, and is sent the whole firmware.
      device(context, old, %{update_mode: :device_managed})
      # Its delta is still being built, which holds the whole release.
      device(context, building)

      {rows, total} = Rollout.unreached(deployment_group, 2)

      assert total == 4

      assert [
               %{device: %Device{id: boxed_id}, state: :penalty_box, delta_source: nil},
               %{device: %Device{id: waiting_id}, state: :delta_failed, delta_source: "1.0.0"}
             ] = rows

      assert boxed_id == boxed.id
      assert waiting_id == waiting.id

      assert Rollout.failed_deltas(deployment_group) == [
               %{version: "0.9.0", devices: 1},
               %{version: "1.0.0", devices: 2}
             ]
    end

    test "holds no one in a group with delta updates off", context do
      %{deployment_group: deployment_group, old_firmware: old, new_firmware: new, product: product} = context

      Fixtures.firmware_delta_fixture(old, new, %{status: :failed})
      device(context, old)

      Repo.update!(Ecto.Changeset.change(deployment_group, delta_updatable: false))
      deployment_group = reload(deployment_group, product)

      assert Rollout.unreached(deployment_group, 5) == {[], 0}
      assert Rollout.failed_deltas(deployment_group) == []
    end

    test "holds no one for firmware that can't take a delta, which is sent whole", context do
      %{deployment_group: deployment_group, old_firmware: old, new_firmware: new, product: product} = context

      Fixtures.firmware_delta_fixture(old, new, %{status: :failed})
      device(context, old)

      Repo.update!(Ecto.Changeset.change(new, delta_updatable: false))
      deployment_group = reload(deployment_group, product)

      assert Rollout.unreached(deployment_group, 5) == {[], 0}
      assert Rollout.failed_deltas(deployment_group) == []
    end
  end

  describe "status/4" do
    test "puts a paused group first, then a stopped or waiting step, then the counts", %{deployment_group: dg} do
      counts = %{Rollout.empty_counts() | total: 3, updated: 2, updates_off: 1}
      step = %DeploymentWorkflowStep{}

      assert Rollout.status(%{dg | is_active: false}, counts, step, nil) == :paused
      assert Rollout.status(dg, counts, step, step) == :stopped
      assert Rollout.status(dg, counts, nil, step) == :awaiting_approval
      assert Rollout.status(dg, Rollout.empty_counts(), nil, nil) == :no_devices
      assert Rollout.status(dg, counts, nil, nil) == :up_to_date
      assert Rollout.status(dg, %{counts | updated: 1, waiting: 1}, nil, nil) == :rolling_out
    end
  end
end
