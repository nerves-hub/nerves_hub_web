defmodule NervesHub.Webhooks.RaisedEventsTest do
  @moduledoc """
  Each subscribable event is raised where it happens, with the payload
  `docs/webhooks.md` promises.

  Drives the code that raises each event and reads back the deliveries it
  queued, rather than calling `NervesHub.Integrations.dispatch/3` directly: what
  matters to a receiver is that a disconnect, say, produces the event at all.
  """
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts.Scope
  alias NervesHub.Analytics.Buffer
  alias NervesHub.DeviceEvents
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.HealthEvaluation
  alias NervesHub.Devices.Updates
  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.ErrorReports.GroupBuffer
  alias NervesHub.Extensions.Health
  alias NervesHub.Extensions.Metrics
  alias NervesHub.Extensions.State
  alias NervesHub.Firmwares
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Cache
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Webhooks
  alias NervesHub.Webhooks.Events
  alias NervesHub.Webhooks.Webhook
  alias NervesHub.Workers.DeliverWebhook

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    scope = %Scope{org: org, product: product, user: user}

    {:ok, _webhook} =
      Webhooks.create_webhook(scope, %{"url" => "https://example.com/hooks", "events" => Events.types()})

    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: org.id,
      product_id: product.id,
      firmware_metadata: device.firmware_metadata
    }

    %{
      device: device,
      device_info: device_info,
      firmware: firmware,
      org: org,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir,
      user: user
    }
  end

  # The events queued so far, as receivers will get them, oldest first.
  defp raised(type) do
    for job <- [worker: DeliverWebhook] |> all_enqueued() |> Enum.sort_by(& &1.id),
        %{"type" => ^type, "data" => data} <- [Jason.decode!(job.args["body"])],
        do: data
  end

  defp device_summary(device) do
    %{
      "identifier" => device.identifier,
      "firmware" => %{
        "uuid" => device.firmware_metadata.uuid,
        "version" => device.firmware_metadata.version,
        "platform" => device.firmware_metadata.platform,
        "architecture" => device.firmware_metadata.architecture
      }
    }
  end

  describe "connection events" do
    test "device.connected", %{device: device, org: org, product: product} do
      {:ok, connection} = Connections.device_connecting(org.id, product.id, device.id)
      assert [] = raised("device.connected")

      :ok = Connections.device_connected(connection.id)

      assert [data] = raised("device.connected")
      assert data["device"] == device_summary(device)
      assert data["connection"]["id"] == connection.id
      assert data["product"] == %{"name" => product.name}
      assert data["org"] == %{"name" => org.name}
    end

    test "device.disconnected", %{device: device, org: org, product: product} do
      {:ok, connection} = Connections.device_connecting(org.id, product.id, device.id)
      :ok = Connections.device_disconnected(connection.id)

      assert [data] = raised("device.disconnected")
      assert data["device"] == device_summary(device)
      assert %{"id" => id, "disconnected_at" => disconnected_at, "reason" => nil} = data["connection"]
      assert id == connection.id
      assert disconnected_at
    end

    test "device.disconnected, for a connection the stale sweep closed", %{device: device, product: product} do
      interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
      long_ago = DateTime.add(DateTime.utc_now(), -(interval + 30), :minute)

      connection =
        Fixtures.device_connection_fixture(device, %{product_id: product.id, last_seen_at: long_ago})

      :ok = Connections.clean_stale_connections()

      assert [data] = raised("device.disconnected")
      assert data["device"] == device_summary(device)
      assert %{"id" => id, "reason" => "Stale connection"} = data["connection"]
      assert id == connection.id
    end
  end

  describe "health events" do
    test "device.health_reported carries the readings as stored", %{device: device, device_info: device_info} do
      # Metadata is merged into the connection, so the report needs one.
      {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
      device_info = %{device_info | connection_ref: connection.id}

      report = %{
        "value" => %{
          "metrics" => %{"cpu_temp" => 41, "uptime" => "a while"},
          "alarms" => %{"DiskFull" => "/data is full"},
          "metadata" => %{"site" => "north"}
        }
      }

      {_state, []} = Health.handle_in("report", report, State.new(device_info))

      assert [data] = raised("device.health_reported")
      assert data["device"] == device_summary(device)
      assert data["metrics"] == %{"cpu_temp" => 41.0}
      assert data["alarms"] == %{"DiskFull" => "/data is full"}
      assert data["metadata"] == %{"site" => "north"}
    end

    test "device.metrics_reported carries the reports that were stored", %{device_info: device_info} do
      now = DateTime.utc_now()

      reports = [
        %{"timestamp" => DateTime.to_iso8601(DateTime.add(now, -60)), "metrics" => %{"fps" => 59}},
        # A clock a year out: skipped by storage, so not passed on either.
        %{"timestamp" => DateTime.to_iso8601(DateTime.add(now, -365, :day)), "metrics" => %{"fps" => 1}}
      ]

      {_state, []} = Metrics.handle_in("report", %{"reports" => reports}, State.new(device_info))

      assert [%{"reports" => [%{"timestamp" => timestamp, "metrics" => %{"fps" => 59.0}}]}] =
               raised("device.metrics_reported")

      assert {:ok, _, 0} = DateTime.from_iso8601(timestamp)
    end
  end

  describe "health status events" do
    defp reading(key, value), do: [{key, DateTime.utc_now(), value}]

    # Stored and flushed, so the next judgement reads it back from ClickHouse.
    defp store_reading(device_info, key, value) do
      {:ok, 1} = NervesHub.Devices.Metrics.record(device_info, %{key => value})
      :ok = Buffer.flush(DeviceMetric)
    end

    test "device.health_status_changed, for a first verdict and each move after it", %{
      device: device,
      device_info: device_info
    } do
      :ok = HealthEvaluation.evaluate_and_save(device_info, reading("cpu_usage_percent", 20.0))

      assert [first] = raised("device.health_status_changed")
      assert %{"status" => "healthy", "previous_status" => nil, "reasons" => nil} = first
      assert first["device"] == device_summary(device)

      # The same verdict again is not a change.
      :ok = HealthEvaluation.evaluate_and_save(device_info, reading("cpu_usage_percent", 21.0))
      assert [_first] = raised("device.health_status_changed")

      for _ <- 1..3, do: store_reading(device_info, "cpu_usage_percent", 95.0)
      :ok = HealthEvaluation.evaluate_and_save(device_info, reading("cpu_usage_percent", 95.0))

      assert [moved] = Enum.reject(raised("device.health_status_changed"), &(&1 == first))
      assert %{"status" => "unhealthy", "previous_status" => "healthy"} = moved
      assert %{"unhealthy" => %{"cpu_usage_percent" => %{"threshold" => 90.0}}} = moved["reasons"]
    end

    test "is not raised for a product with no webhook wanting it", %{device_info: device_info} do
      Webhook |> Repo.all() |> Enum.each(&Repo.delete!/1)
      Cache.reset()

      :ok = HealthEvaluation.evaluate_and_save(device_info, reading("cpu_usage_percent", 20.0))

      assert [] = raised("device.health_status_changed")
    end
  end

  describe "firmware events" do
    test "device.firmware_update.scheduled, for an update a user pushed", context do
      %{device: device, org_key: org_key, product: product, tmp_dir: tmp_dir, user: user} = context
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, _device} = DeviceEvents.manual_update(device, new_firmware, user)

      assert [data] = raised("device.firmware_update.scheduled")
      assert data["firmware"] == %{"uuid" => new_firmware.uuid, "version" => new_firmware.version}
      assert data["initiated_by"] == "user"
      assert data["deployment_group"] == nil
    end

    test "device.firmware_update.scheduled, for a deployment group's update", context do
      %{device: device, org_key: org_key, product: product, tmp_dir: tmp_dir, user: user} = context
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      deployment_group =
        new_firmware
        |> Fixtures.deployment_group_fixture(%{is_active: true, user: user})
        |> Repo.preload(:org)

      {:ok, _inflight_update} = DeviceEvents.schedule_update(device.id, deployment_group)

      assert [data] = raised("device.firmware_update.scheduled")
      assert data["firmware"]["uuid"] == new_firmware.uuid
      assert data["initiated_by"] == "deployment_group"
      assert data["deployment_group"] == %{"name" => deployment_group.name}
    end

    test "nothing is scheduled when the deployment group has nothing to send", %{
      device: device,
      firmware: firmware,
      user: user
    } do
      deployment_group = firmware |> Fixtures.deployment_group_fixture(%{user: user}) |> Repo.preload(:org)

      {:ok, _inflight_update} = DeviceEvents.schedule_update(device.id, deployment_group)

      assert [] = raised("device.firmware_update.scheduled")
    end

    test "device.firmware_update.progress follows stage changes, not every percent", %{device: device} do
      :ok = FirmwareUpdates.status_update("downloading", device.id, %{"progress" => 10})
      :ok = FirmwareUpdates.status_update("downloading", device.id, %{"progress" => 11})
      :ok = FirmwareUpdates.status_update("updating", device.id, %{"progress" => 50})

      assert [first, second] = Enum.sort_by(raised("device.firmware_update.progress"), & &1["progress"])
      assert %{"status" => "downloading", "progress" => 10} = first
      assert %{"status" => "updating", "progress" => 50} = second
      assert first["device"] == device_summary(device)
    end

    test "device.firmware_update.finished, for a failed update", %{device: device, firmware: firmware} do
      :ok = FirmwareUpdates.status_update("failed", device.id, %{"reason" => "fwup error: bad signature"})

      assert [data] = raised("device.firmware_update.finished")
      assert data["outcome"] == "failed"
      assert data["reason"] == "fwup error: bad signature"
      assert data["source_firmware"] == %{"uuid" => firmware.uuid, "version" => firmware.version}
      assert data["device"] == device_summary(device)
    end

    test "device.firmware_update.finished, for a successful update", context do
      %{device: device, firmware: firmware, org_key: org_key, product: product, tmp_dir: tmp_dir} = context
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      {:ok, new_metadata} = NervesHub.Firmwares.metadata_from_firmware(new_firmware)

      updated = %{device | firmware_metadata: new_metadata}
      {:ok, _device} = FirmwareUpdates.firmware_update_successful(updated, device.firmware_metadata)

      assert [data] = raised("device.firmware_update.finished")
      assert data["outcome"] == "succeeded"
      assert data["reason"] == nil
      assert data["source_firmware"]["uuid"] == firmware.uuid
      assert data["target_firmware"] == %{"uuid" => new_firmware.uuid, "version" => new_firmware.version}
      assert data["device"]["firmware"]["uuid"] == new_firmware.uuid
    end

    test "device.firmware_validated", %{device: device, device_info: device_info} do
      # Validation is recorded against the device's firmware history row.
      Devices.update_firmware_metadata(device, Map.from_struct(device.firmware_metadata), :not_validated, false)

      :ok = Updates.firmware_validated(device_info)

      assert [data] = raised("device.firmware_validated")
      assert data["device"] == device_summary(device)
    end
  end

  describe "error events" do
    test "a new error, and a resolved one happening again", %{device_info: device_info, user: user} do
      report = %{
        "timestamp" => "2026-10-14T09:00:00.000000Z",
        "kind" => "error",
        "reason" => "** (RuntimeError) boom",
        "frames" => [
          %{"module" => "MyApp.Worker", "function" => "handle_info/2", "file" => "lib/worker.ex", "line" => 42}
        ]
      }

      {:ok, _} = NervesHub.ErrorReports.record(device_info, report)
      :ok = GroupBuffer.flush()

      assert [%{"error" => error} = data] = raised("error_group.created")
      refute Map.has_key?(data, "device")

      assert %{
               "reason" => "** (RuntimeError) boom",
               "top_frame" => "MyApp.Worker.handle_info/2 (lib/worker.ex:42)",
               "occurrence_count" => 1
             } = error

      {:ok, _} =
        ErrorGroup
        |> Repo.get!(error["id"])
        |> ErrorGroup.resolve_changeset(user)
        |> Repo.update()

      {:ok, _} = NervesHub.ErrorReports.record(device_info, %{report | "timestamp" => "2026-10-14T10:00:00.000000Z"})
      :ok = GroupBuffer.flush()

      assert [%{"error" => %{"id" => id, "occurrence_count" => 2}}] = raised("error_group.reopened")
      assert id == error["id"]
    end
  end

  describe "deployment workflow events" do
    @workflow %{
      "version" => 1,
      "steps" => [
        %{
          "name" => "Canary",
          "matching_conditions" => %{"tags" => ["canary"]},
          "failure_tolerance" => %{"devices" => 1}
        },
        %{"name" => "Sign-off", "type" => "approval_required"}
      ]
    }

    # A deployment group whose current release walks @workflow, with one
    # online canary in it.
    defp workflow_release(context) do
      %{firmware: firmware, org: org, org_key: org_key, product: product, tmp_dir: tmp_dir, user: user} = context

      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user, is_active: true})

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: @workflow}, user)

      canary = Fixtures.device_fixture(org, product, firmware, %{tags: ["canary"], deployment_id: deployment_group.id})
      {:ok, connection} = Connections.device_connecting(org.id, product.id, canary.id)
      :ok = Connections.device_connected(connection.id)

      next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "0.0.2", dir: tmp_dir})

      {:ok, {release, _}} =
        ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{}, broadcast: false)

      {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group.id)

      %{canary: canary, deployment_group: deployment_group, next_firmware: next_firmware, release: release}
    end

    defp release_step(release, number), do: release.id |> Workflows.release_steps() |> Enum.at(number - 1)

    test "a workflow walked to the end announces each step", context do
      %{canary: canary, deployment_group: deployment_group, next_firmware: next_firmware, release: release} =
        workflow_release(context)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert [started] = raised("deployment_group.workflow_step.started")

      canary_step = release_step(release, 1)

      assert %{
               "org" => %{"name" => org_name},
               "product" => %{"name" => product_name},
               "deployment_group" => %{"name" => group_name},
               "release" => %{"number" => release_number, "firmware" => %{"uuid" => uuid, "version" => "0.0.2"}},
               "workflow" => %{"steps" => 3},
               "step" => %{
                 "id" => step_id,
                 "number" => 1,
                 "name" => "Canary",
                 "type" => "update_devices",
                 "status" => "in_progress",
                 "started_at" => started_at,
                 "finished_at" => nil
               },
               "user" => nil,
               "failed_devices" => nil
             } = started

      assert {org_name, product_name, group_name} == {context.org.name, context.product.name, deployment_group.name}
      assert {release_number, uuid, step_id} == {release.number, next_firmware.uuid, canary_step.id}
      assert {:ok, _, 0} = DateTime.from_iso8601(started_at)

      {:ok, metadata} = Firmwares.metadata_from_firmware(next_firmware)
      {:ok, _} = Devices.update_firmware_metadata(canary, metadata, :validated, false)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert [%{"step" => %{"number" => 1, "status" => "completed"}, "user" => nil}] =
               raised("deployment_group.workflow_step.completed")

      # An approval step only waits, so it is announced as waiting rather than
      # as started.
      assert [%{"step" => %{"number" => 2, "name" => "Sign-off", "type" => "approval_required"}}] =
               raised("deployment_group.workflow_step.awaiting_approval")

      assert [_canary_only] = raised("deployment_group.workflow_step.started")

      {:ok, _} = Workflows.approve_step(release_step(release, 2), context.user)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      user_name = context.user.name

      assert [_canary, %{"step" => %{"number" => 2}, "user" => %{"name" => ^user_name}}] =
               raised("deployment_group.workflow_step.completed")

      assert [_canary, %{"step" => %{"number" => 3, "name" => "Remaining devices", "type" => "catch_all"}}] =
               raised("deployment_group.workflow_step.started")
    end

    test "a failed step says how many devices failed, and retrying and skipping say who", context do
      %{canary: canary, deployment_group: deployment_group, release: release} = workflow_release(context)

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      canary
      |> Ecto.Changeset.change(%{
        updates_blocked_until: DateTime.add(DateTime.utc_now(:second), 3600),
        update_attempts: [DateTime.utc_now(:second)]
      })
      |> Repo.update!()

      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      assert [%{"step" => %{"number" => 1, "status" => "error"}, "failed_devices" => 1}] =
               raised("deployment_group.workflow_step.failed")

      user_name = context.user.name

      {:ok, _} = Workflows.retry_step(deployment_group, release_step(release, 1), context.user)

      assert [%{"user" => nil}, %{"step" => %{"number" => 1}, "user" => %{"name" => ^user_name}}] =
               raised("deployment_group.workflow_step.started")

      {:ok, _} = Workflows.skip_step(release_step(release, 1), context.user)

      assert [%{"step" => %{"number" => 1, "status" => "skipped"}, "user" => %{"name" => ^user_name}}] =
               raised("deployment_group.workflow_step.skipped")
    end
  end
end
