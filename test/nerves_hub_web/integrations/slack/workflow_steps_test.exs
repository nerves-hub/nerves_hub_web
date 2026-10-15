defmodule NervesHubWeb.Integrations.Slack.WorkflowStepsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Connections
  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Claims
  alias NervesHub.Integrations.Slack.UserLink
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Workers.UpdateSlackWorkflowMessage
  alias NervesHubWeb.Integrations.Slack.Actions
  alias NervesHubWeb.Integrations.Slack.WorkflowSteps
  alias Phoenix.Socket.Broadcast

  @moduletag :tmp_dir

  @response_url "https://hooks.slack.com/actions/T0ACME/1/abc"

  @workflow %{
    "version" => 1,
    "steps" => [
      %{"name" => "Sign-off", "type" => "approval_required"},
      %{
        "name" => "Canary",
        "matching_conditions" => %{"tags" => ["canary"]},
        "failure_tolerance" => %{"devices" => 1}
      }
    ]
  }

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

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

    _slack = Fixtures.slack_connection_fixture(org, user, %{team_id: "T0ACME"})

    test_pid = self()

    Req.Test.stub(Slack, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:slack, conn.host, conn.request_path, body})

      case conn.host do
        "hooks.slack.com" -> Plug.Conn.send_resp(conn, 200, "ok")
        _api -> Req.Test.json(conn, %{"ok" => true})
      end
    end)

    %{
      canary: canary,
      deployment_group: deployment_group,
      next_firmware: next_firmware,
      org: org,
      org_key: org_key,
      release: release,
      tmp_dir: tmp_dir,
      user: user
    }
  end

  defp link!(user, slack_user_id \\ "U0ALICE") do
    NervesHub.Repo.insert!(%UserLink{
      user_id: user.id,
      team_id: "T0ACME",
      slack_user_id: slack_user_id,
      slack_name: "Alice",
      linked_at: DateTime.utc_now()
    })

    :ok
  end

  defp click(action, step, overrides \\ %{}) do
    Map.merge(
      %{
        action: action,
        step_id: step.id,
        team_id: "T0ACME",
        slack_user_id: "U0ALICE",
        slack_username: "alice",
        response_url: @response_url,
        channel_id: "C0FLEET",
        message_ts: "1728900000.000100"
      },
      overrides
    )
  end

  defp step(release, number), do: release.id |> Workflows.release_steps() |> Enum.at(number - 1)

  defp private_reply() do
    assert_received {:slack, "hooks.slack.com", "/actions/T0ACME/1/abc", body}
    assert %{"response_type" => "ephemeral", "replace_original" => false, "text" => text} = Jason.decode!(body)
    text
  end

  defp thread_reply() do
    assert_received {:slack, "slack.com", "/api/chat.postMessage", body}
    assert %{"channel" => "C0FLEET", "thread_ts" => "1728900000.000100", "text" => text} = Jason.decode!(body)
    text
  end

  # Takes the workflow past Sign-off to Canary, then fails Canary.
  defp fail_canary(%{canary: canary, deployment_group: deployment_group, release: release, user: user}) do
    _ = WorkflowCoordinator.schedule_updates(deployment_group)
    _ = Workflows.approve_step(step(release, 1), user)
    _ = WorkflowCoordinator.schedule_updates(deployment_group)
    _ = WorkflowCoordinator.schedule_updates(deployment_group)

    canary
    |> Ecto.Changeset.change(%{
      updates_blocked_until: DateTime.add(DateTime.utc_now(:second), 3600),
      update_attempts: [DateTime.utc_now(:second)]
    })
    |> NervesHub.Repo.update!()

    _ = WorkflowCoordinator.schedule_updates(deployment_group)

    failed = step(release, 2)
    assert failed.status == :error
    failed
  end

  describe "approving" do
    setup %{deployment_group: deployment_group} do
      _ = WorkflowCoordinator.schedule_updates(deployment_group)
      :ok
    end

    test "approves the step as the linked user, audits it, and says so in the thread", context do
      %{deployment_group: deployment_group, release: release, user: user} = context
      :ok = link!(user)
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment_group.id}")

      assert {:ok, :approve} = WorkflowSteps.perform(click(:approve, step(release, 1)))

      approved = step(release, 1)
      assert approved.approved_by_id == user.id

      # The orchestrator is what completes the step, so it is nudged.
      assert_receive %Broadcast{event: "deployments/update"}

      assert [log | _] = AuditLogs.logs_for(deployment_group)

      assert log.description ==
               "User #{user.name} approved workflow step 1 (Sign-off) for deployment group #{deployment_group.name} from Slack user U0ALICE (@alice, workspace T0ACME)"

      assert thread_reply() ==
               ":white_check_mark: #{user.name} approved *Sign-off* for *#{deployment_group.name}* from Slack. The rollout carries on."
    end

    test "a message being kept up to date is edited, not replied to in its thread", %{release: release, user: user} do
      :ok = link!(user)
      sign_off = step(release, 1)

      subscription =
        Repo.insert!(%Slack.Subscription{
          connection_id: Repo.one!(Slack.Connection).id,
          channel_id: "C0FLEET",
          channel_name: "fleet",
          events: ["deployment_group.workflow_step.awaiting_approval"]
        })

      message =
        Repo.insert!(%Slack.WorkflowMessage{
          subscription_id: subscription.id,
          channel_id: "C0FLEET",
          ts: "1728900000.000100",
          type: "deployment_group.workflow_step.awaiting_approval",
          events: [%{"step" => %{"id" => sign_off.id, "name" => "Sign-off"}}],
          step_ids: [sign_off.id]
        })

      assert {:ok, :approve} = WorkflowSteps.perform(click(:approve, sign_off))

      refute_received {:slack, "slack.com", "/api/chat.postMessage", _body}
      assert %{"change" => "approved"} = Repo.reload!(message).resolutions[Integer.to_string(sign_off.id)]
      assert [_job] = all_enqueued(worker: UpdateSlackWorkflowMessage, args: %{workflow_message_id: message.id})
    end

    test "a step already approved is not approved again, and says by whom", %{release: release, user: user} do
      :ok = link!(user)

      assert {:ok, :approve} = WorkflowSteps.perform(click(:approve, step(release, 1)))
      assert {:error, :already_done} = WorkflowSteps.perform(click(:approve, step(release, 1)))

      assert private_reply() == "*Sign-off* was already approved by #{user.name}."
    end

    test "two clicks at once act once", %{release: release, user: user} do
      :ok = link!(user)
      :ok = Claims.claim("workflow_step:#{step(release, 1).id}", 30, "Bob")

      assert {:error, :just_done} = WorkflowSteps.perform(click(:approve, step(release, 1)))
      assert is_nil(step(release, 1).approved_at)
      assert private_reply() =~ "was acted on from Slack by Bob a moment ago"
    end

    test "a step of an earlier release is left alone", context do
      %{deployment_group: deployment_group, org_key: org_key, release: release, tmp_dir: tmp_dir, user: user} = context
      :ok = link!(user)

      newer = Fixtures.firmware_fixture(org_key, deployment_group.product, %{version: "0.0.3", dir: tmp_dir})

      {:ok, _} =
        ManagedDeployments.create_deployment_release(deployment_group, newer, nil, user, %{}, broadcast: false)

      assert {:error, :superseded} = WorkflowSteps.perform(click(:approve, step(release, 1)))
      assert private_reply() =~ "is part of an earlier release of"
    end
  end

  describe "retrying and skipping a failed step" do
    test "retry starts it again", context do
      %{deployment_group: deployment_group, user: user} = context
      :ok = link!(user)
      failed = fail_canary(context)

      assert {:ok, :retry} = WorkflowSteps.perform(click(:retry, failed))
      assert step(context.release, 2).status == :in_progress

      assert [log | _] = AuditLogs.logs_for(deployment_group)
      assert log.description =~ "User #{user.name} retried workflow step 2 (Canary)"
      assert log.description =~ "from Slack user U0ALICE"

      assert thread_reply() =~ "retried *Canary*"
    end

    test "skip moves the workflow past it", context do
      :ok = link!(context.user)
      failed = fail_canary(context)

      assert {:ok, :skip} = WorkflowSteps.perform(click(:skip, failed))
      assert step(context.release, 2).status == :skipped

      assert thread_reply() =~ "skipped *Canary*"
    end

    test "a step that is running again cannot be retried", context do
      :ok = link!(context.user)
      failed = fail_canary(context)

      {:ok, _} = Workflows.retry_step(context.deployment_group, failed, context.user)

      assert {:error, :not_retryable} = WorkflowSteps.perform(click(:retry, failed))
      assert private_reply() == "Only a failed step can be retried, and *Canary* is running."
    end
  end

  describe "who may" do
    test "a Slack user who is not linked is asked to link first", %{release: release} do
      assert {:error, :not_linked} = WorkflowSteps.perform(click(:approve, step(release, 1)))
    end

    test "a viewer cannot approve", %{org: org, release: release} do
      viewer = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, viewer, %{role: :view})
      :ok = link!(viewer)

      assert {:error, :not_allowed} = WorkflowSteps.perform(click(:approve, step(release, 1)))
      assert private_reply() == "Your role in NervesHub does not let you approve deployment workflow steps."
    end

    test "a workspace the organization is not connected to cannot", %{release: release, user: user} do
      :ok = link!(user)

      _other =
        Fixtures.slack_connection_fixture(Fixtures.org_fixture(user, %{name: "other"}), user, %{team_id: "T0OTHER"})

      NervesHub.Repo.insert!(%UserLink{
        user_id: user.id,
        team_id: "T0OTHER",
        slack_user_id: "U0ALICE",
        slack_name: "Alice",
        linked_at: DateTime.utc_now()
      })

      assert {:error, :not_connected} =
               WorkflowSteps.perform(click(:approve, step(release, 1), %{team_id: "T0OTHER", response_url: nil}))
    end

    test "a step that no longer exists", %{user: user} do
      :ok = link!(user)
      assert {:error, :no_step} = WorkflowSteps.perform(click(:approve, %{id: 0}))
    end
  end

  describe "a click from Slack" do
    test "is carried out in the background", %{deployment_group: deployment_group, release: release, user: user} do
      :ok = link!(user)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      payload = %{
        "type" => "block_actions",
        "team" => %{"id" => "T0ACME"},
        "user" => %{"id" => "U0ALICE", "username" => "alice"},
        "response_url" => @response_url,
        "container" => %{"channel_id" => "C0FLEET", "message_ts" => "1728900000.000100"},
        "actions" => [%{"action_id" => "workflow_step.approve", "value" => Integer.to_string(step(release, 1).id)}]
      }

      assert :ok = Actions.handle_interaction(payload)
      assert_receive {:slack, "slack.com", "/api/chat.postMessage", _body}, 2000
      assert step(release, 1).approved_by_id == user.id
    end

    test "that names no step is ignored" do
      payload = %{"team" => %{"id" => "T0ACME"}, "user" => %{"id" => "U0ALICE"}}

      assert WorkflowSteps.click(payload, %{"action_id" => "workflow_step.approve", "value" => "nope"}) == nil
      assert WorkflowSteps.click(payload, %{"action_id" => "workflow_step.explode", "value" => "1"}) == nil
    end
  end
end
