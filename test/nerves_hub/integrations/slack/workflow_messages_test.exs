defmodule NervesHub.Integrations.Slack.WorkflowMessagesTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHub.Integrations
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Subscriptions
  alias NervesHub.Integrations.Slack.WorkflowMessage
  alias NervesHub.Integrations.Slack.WorkflowMessages
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Workers.UpdateSlackWorkflowMessage

  @moduletag :tmp_dir

  @awaiting "deployment_group.workflow_step.awaiting_approval"
  @failed "deployment_group.workflow_step.failed"

  setup do
    user = Fixtures.user_fixture(%{name: "Alice"})
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org, %{name: "thermostat"})
    connection = Fixtures.slack_connection_fixture(org, user)
    scope = %Scope{org: org, user: user, role: :admin}

    {:ok, subscription} =
      Subscriptions.create_subscription(scope, connection, %{
        "channel_id" => "C0FLEET",
        "channel_name" => "fleet",
        "events" => [@awaiting, @failed, "device.health_status_changed"]
      })

    %{org: org, product: product, scope: scope, subscription: subscription, user: user}
  end

  # Answers chat.postMessage with a `ts` of its own and chat.update with
  # `update`, and tells the test what was sent.
  defp stub_slack(update \\ %{"ok" => true}) do
    test_pid = self()

    Req.Test.stub(Slack, fn conn ->
      method = List.last(conn.path_info)
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(body)
      send(test_pid, {:slack, method, body})

      case method do
        "chat.postMessage" ->
          Req.Test.json(conn, %{"ok" => true, "channel" => body["channel"], "ts" => "1728.0001"})

        "chat.update" ->
          case update do
            {status, answer} -> conn |> Plug.Conn.put_status(status) |> Req.Test.json(answer)
            answer -> Req.Test.json(conn, answer)
          end
      end
    end)
  end

  defp step_event(product, step_id, name \\ "Sign-off") do
    :ok =
      Integrations.dispatch(product.id, @awaiting, fn ->
        %{
          deployment_group: %{name: "production"},
          release: %{number: 4, firmware: %{uuid: "u", version: "1.2.0"}},
          workflow: %{steps: 3},
          step: %{id: step_id, number: 2, name: name}
        }
      end)
  end

  defp actions(blocks), do: for(%{"type" => "actions"} = block <- blocks, do: block)
  defp contexts(blocks), do: for(%{"type" => "context", "elements" => [%{"text" => text}]} <- blocks, do: text)

  describe "recording" do
    test "a message with buttons for steps is recorded as it is posted", %{product: product, subscription: subscription} do
      stub_slack()
      step_event(product, 42)

      assert :ok = Subscriptions.post_pending_events(subscription.id)

      assert [%WorkflowMessage{channel_id: "C0FLEET", ts: "1728.0001", type: @awaiting, step_ids: [42]}] =
               Repo.all(WorkflowMessage)

      assert WorkflowMessages.recorded?("C0FLEET", "1728.0001")
      refute WorkflowMessages.recorded?("C0FLEET", "1728.0002")
    end

    test "a message without buttons is not", %{product: product, subscription: subscription} do
      stub_slack()

      :ok =
        Integrations.dispatch(product.id, "device.health_status_changed", fn ->
          %{device: %{identifier: "nh-1"}, status: "warning", previous_status: "healthy", reasons: nil}
        end)

      assert :ok = Subscriptions.post_pending_events(subscription.id)
      assert Repo.all(WorkflowMessage) == []
    end

    test "messages older than 30 days are forgotten", %{product: product, subscription: subscription} do
      stub_slack()
      step_event(product, 1)
      :ok = Subscriptions.post_pending_events(subscription.id)
      {1, _} = Repo.update_all(WorkflowMessage, set: [inserted_at: DateTime.add(DateTime.utc_now(), -31, :day)])

      step_event(product, 2)
      :ok = Subscriptions.post_pending_events(subscription.id)

      assert [%WorkflowMessage{step_ids: [2]}] = Repo.all(WorkflowMessage)
    end
  end

  describe "resolving and editing" do
    setup %{product: product, subscription: subscription} do
      stub_slack()
      step_event(product, 42)
      step_event(product, 43, "Second sign-off")
      :ok = Subscriptions.post_pending_events(subscription.id)
      assert_received {:slack, "chat.postMessage", _}

      %{message: Repo.one!(WorkflowMessage)}
    end

    test "the step's buttons give way to who dealt with it; the others' stay", %{message: message} do
      :ok = WorkflowMessages.resolve([42], %{"change" => "approved", "by" => "Alice"})

      assert [_job] = all_enqueued(worker: UpdateSlackWorkflowMessage, args: %{workflow_message_id: message.id})
      assert :ok = perform_job(UpdateSlackWorkflowMessage, %{workflow_message_id: message.id})

      assert_received {:slack, "chat.update", %{"channel" => "C0FLEET", "ts" => "1728.0001", "blocks" => blocks}}
      assert ":white_check_mark: Approved by Alice" in contexts(blocks)
      assert [%{"elements" => [%{"action_id" => "workflow_step.approve", "value" => "43"} | _]}] = actions(blocks)

      # One step is still waiting, so the message is still kept.
      assert Repo.reload(message)
    end

    test "is forgotten once every step on it was dealt with", %{message: message} do
      :ok = WorkflowMessages.resolve([42, 43], %{"change" => "skipped", "by" => "Bob"})
      assert :ok = perform_job(UpdateSlackWorkflowMessage, %{workflow_message_id: message.id})

      assert_received {:slack, "chat.update", %{"blocks" => blocks}}
      assert actions(blocks) == []
      assert Repo.reload(message) == nil
    end

    test "the first thing done to a step is what it says", %{message: message} do
      :ok = WorkflowMessages.resolve([42], %{"change" => "approved", "by" => "Alice"})
      :ok = WorkflowMessages.resolve([42], %{"change" => "replaced", "release" => 5})

      assert %{resolutions: %{"42" => %{"change" => "approved", "by" => "Alice"}}} = Repo.reload!(message)
    end

    test "a message Slack can no longer edit is forgotten", %{message: message} do
      stub_slack(%{"ok" => false, "error" => "message_not_found"})
      :ok = WorkflowMessages.resolve([42], %{"change" => "approved", "by" => "Alice"})

      assert :ok = perform_job(UpdateSlackWorkflowMessage, %{workflow_message_id: message.id})
      assert Repo.reload(message) == nil
    end

    test "waits as long as Slack asks", %{message: message} do
      stub_slack({429, %{"ok" => false, "error" => "ratelimited"}})
      :ok = WorkflowMessages.resolve([42], %{"change" => "approved", "by" => "Alice"})

      assert {:snooze, 30} = perform_job(UpdateSlackWorkflowMessage, %{workflow_message_id: message.id})
    end

    test "a step on no message queues nothing" do
      :ok = WorkflowMessages.resolve([999], %{"change" => "approved", "by" => "Alice"})
      assert all_enqueued(worker: UpdateSlackWorkflowMessage) == []
    end
  end

  describe "when a workflow moves" do
    @workflow %{
      "version" => 1,
      "steps" => [%{"name" => "Sign-off", "type" => "approval_required"}]
    }

    setup %{org: org, product: product, subscription: subscription, user: user, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user, is_active: true})

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: @workflow}, user)

      next = Fixtures.firmware_fixture(org_key, product, %{version: "0.0.2", dir: tmp_dir})

      {:ok, {release, _}} =
        ManagedDeployments.create_deployment_release(deployment_group, next, nil, user, %{}, broadcast: false)

      {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group.id)
      _ = WorkflowCoordinator.schedule_updates(deployment_group)

      sign_off = release.id |> Workflows.release_steps() |> hd()

      Repo.insert!(%WorkflowMessage{
        subscription_id: subscription.id,
        channel_id: "C0FLEET",
        ts: "1728.0009",
        type: @awaiting,
        events: [%{"step" => %{"id" => sign_off.id, "name" => "Sign-off"}}],
        step_ids: [sign_off.id]
      })

      %{deployment_group: deployment_group, org_key: org_key, sign_off: sign_off}
    end

    defp resolution(step), do: Repo.one!(WorkflowMessage).resolutions[Integer.to_string(step.id)]

    test "approving a step, from anywhere, says so on its messages", %{sign_off: sign_off, user: user} do
      {:ok, _} = Workflows.approve_step(sign_off, user)

      assert %{"change" => "approved", "by" => "Alice"} = resolution(sign_off)
      assert [_job] = all_enqueued(worker: UpdateSlackWorkflowMessage)
    end

    test "skipping one says so too", %{sign_off: sign_off, user: user} do
      {:ok, _} = Workflows.skip_step(sign_off, user)
      assert %{"change" => "skipped", "by" => "Alice"} = resolution(sign_off)
    end

    test "a new release says the old release's steps were left behind", context do
      %{deployment_group: deployment_group, org_key: org_key, product: product, sign_off: sign_off, tmp_dir: tmp_dir} =
        context

      newer = Fixtures.firmware_fixture(org_key, product, %{version: "0.0.3", dir: tmp_dir})

      {:ok, {release, _}} =
        ManagedDeployments.create_deployment_release(deployment_group, newer, nil, context.user, %{}, broadcast: false)

      assert %{"change" => "replaced", "release" => number} = resolution(sign_off)
      assert number == release.number
    end
  end
end
