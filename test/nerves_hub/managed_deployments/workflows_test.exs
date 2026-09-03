defmodule NervesHub.ManagedDeployments.WorkflowsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Updates
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  @definition %{
    "version" => 1,
    "steps" => [
      %{
        "name" => "Canary",
        "description" => "wired canary devices",
        "matching_conditions" => %{"tags" => ["canary"], "network_interfaces" => ["ethernet"], "match_limit" => 20},
        "concurrent_updates" => 10
      },
      %{"name" => "Everyone else", "concurrent_updates" => 25}
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

  defp with_workflow(context, definition \\ @definition) do
    %{deployment_group: deployment_group, user: user, org_key: org_key, product: product} = context

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: definition}, user)

    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "0.0.2"})

    {:ok, {release, deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{}, broadcast: false)

    %{release: release, deployment_group: deployment_group, next_firmware: next_firmware}
  end

  describe "workflow steps on a new release" do
    test "a definition is expanded into ordered steps with a trailing catch_all", context do
      %{release: release} = with_workflow(context)

      steps = Repo.preload(release, :steps).steps

      assert Enum.map(steps, & &1.number) == [1, 2, 3]
      assert Enum.map(steps, & &1.type) == [:update_devices, :update_devices, :catch_all]
      assert Enum.map(steps, & &1.status) == [:waiting, :waiting, :waiting]

      assert [canary, everyone_else, _catch_all] = steps
      assert canary.name == "Canary"
      assert canary.concurrency == 10
      assert canary.matching_conditions.tags == ["canary"]
      assert everyone_else.concurrency == 25
    end

    test "a definition ending in an explicit catch_all does not gain a second one", context do
      definition = %{
        "version" => 1,
        "steps" => [%{"name" => "Canary"}, %{"name" => "Everyone else", "type" => "catch_all"}]
      }

      %{release: release} = with_workflow(context, definition)

      steps = Repo.preload(release, :steps).steps

      assert Enum.map(steps, & &1.type) == [:update_devices, :catch_all]
    end

    # The schema will not let an empty list through, so this only arrives from
    # something that wrote the column directly. Release creation should still work.
    test "a definition with no steps still produces a catch_all", context do
      assert [catch_all] = steps_for_definition(context, %{"version" => 1, "steps" => []})

      assert catch_all.type == :catch_all
      assert catch_all.number == 1
    end

    test "a definition with no steps key at all is survivable", context do
      assert [catch_all] = steps_for_definition(context, %{"version" => 1})

      assert catch_all.type == :catch_all
    end

    test "a deployment group without a workflow gets no steps", context do
      %{deployment_group: deployment_group, user: user, org_key: org_key, product: product} = context

      next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "0.0.2"})

      {:ok, {release, _deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{}, broadcast: false)

      assert Repo.preload(release, :steps).steps == []
    end
  end

  # Written straight to the column, since the changeset would reject it, and
  # released against the firmware already to hand.
  defp steps_for_definition(context, definition) do
    %{deployment_group: deployment_group, user: user, firmware: firmware} = context

    deployment_group
    |> Ecto.Changeset.change(%{workflow_definition: definition})
    |> Repo.update!()

    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group.id)

    {:ok, {release, _}} =
      ManagedDeployments.create_deployment_release(deployment_group, firmware, nil, user, %{}, broadcast: false)

    Repo.preload(release, :steps).steps
  end

  describe "current release preloading" do
    test "steps are preloaded so the orchestrator can pick a coordinator", context do
      %{deployment_group: deployment_group} = with_workflow(context)

      {:ok, reloaded} = ManagedDeployments.get_deployment_group(deployment_group.id)

      assert length(reloaded.current_release.steps) == 3
    end

    # A left join to a has_many multiplies the parent rows. Callers that join the
    # current release only to filter (rather than to preload it) must not see the
    # steps join, or a device is returned once per step and the concurrency limit
    # stops meaning anything.
    test "available_for_update returns each device once, whatever the step count", context do
      %{deployment_group: deployment_group} = with_workflow(context)
      %{org: org, product: product, firmware: firmware} = context

      device = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})

      {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
      :ok = Connections.device_connected(connection.id)

      {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group.id)

      assert length(deployment_group.current_release.steps) == 3
      assert [returned] = Updates.available_for_update(deployment_group, 10)
      assert returned.id == device.id
    end
  end

  describe "start_step/1 and complete_step/1" do
    test "a step moves through in_progress to completed, broadcasting each time", context do
      %{release: release} = with_workflow(context)

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "deployment_release:#{release.id}")

      [step | _] = Repo.preload(release, :steps).steps

      started = Workflows.start_step(step)

      assert started.status == :in_progress
      assert started.started_at
      assert_receive %Broadcast{event: "step/updated", payload: %{number: 1, status: :in_progress}}

      completed = Workflows.complete_step(started)

      assert completed.status == :completed
      assert completed.finished_at
      assert_receive %Broadcast{event: "step/updated", payload: %{number: 1, status: :completed}}
    end
  end
end
