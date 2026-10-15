defmodule NervesHub.Integrations.Slack.SubscriptionsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.Integrations
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.PendingEvent
  alias NervesHub.Integrations.Slack.Subscription
  alias NervesHub.Integrations.Slack.Subscriptions
  alias NervesHub.Products.Notification
  alias NervesHub.Workers.PostSlackEvents

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org, %{name: "thermostat"})
    connection = Fixtures.slack_connection_fixture(org, user)

    %{
      connection: connection,
      org: org,
      product: product,
      scope: %Scope{org: org, user: user, role: :admin},
      user: user
    }
  end

  defp subscription_fixture(%{scope: scope, connection: connection}, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{"channel_id" => "C0FLEET", "channel_name" => "fleet", "events" => ["device.health_status_changed"]},
        attrs
      )

    {:ok, subscription} = Subscriptions.create_subscription(scope, connection, attrs)
    subscription
  end

  # Answers each Slack method with what `answers` says, and tells the test
  # what was posted.
  defp stub_slack(answers) do
    test_pid = self()

    Req.Test.stub(Slack, fn conn ->
      method = List.last(conn.path_info)
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:slack, method, body})

      case Map.fetch!(answers, method) do
        {status, headers, answer} ->
          conn
          |> Plug.Conn.merge_resp_headers(headers)
          |> Plug.Conn.put_status(status)
          |> Req.Test.json(answer)

        answer ->
          Req.Test.json(conn, answer)
      end
    end)
  end

  defp health_change(product_id, identifier, status \\ "unhealthy") do
    :ok =
      Integrations.dispatch(product_id, "device.health_status_changed", fn ->
        %{device: %{identifier: identifier}, status: status, previous_status: "healthy", reasons: nil}
      end)
  end

  describe "create_subscription/3" do
    test "posts the chosen events to the channel, and audits it", %{org: org} = context do
      subscription = subscription_fixture(context)

      assert %Subscription{channel_name: "fleet", enabled: true, all_products: true} = subscription

      assert [log | _] = AuditLogs.logs_for(org)
      assert log.description =~ "started posting Health status changed from every product to Slack channel #fleet"
    end

    test "is limited to the organization's own products", %{user: user} = context do
      other_org = Fixtures.org_fixture(user, %{name: "elsewhere"})
      _theirs = Fixtures.product_fixture(user, other_org, %{name: "theirs"})

      assert {:error, changeset} =
               Subscriptions.create_subscription(context.scope, context.connection, %{
                 "channel_id" => "C1",
                 "channel_name" => "fleet",
                 "events" => ["device.health_status_changed"],
                 "products" => ["theirs"]
               })

      assert %{products: ["has no product named theirs"]} = errors_on(changeset)
    end

    test "refuses a connection of another organization", %{connection: connection, user: user} do
      other_org = Fixtures.org_fixture(user, %{name: "elsewhere"})
      other_scope = %Scope{org: other_org, user: user, role: :admin}

      assert_raise FunctionClauseError, fn ->
        Subscriptions.create_subscription(other_scope, connection, %{"channel_id" => "C1", "channel_name" => "x"})
      end
    end

    test "needs an event, and a channel only once per workspace", context do
      assert {:error, changeset} =
               Subscriptions.create_subscription(context.scope, context.connection, %{
                 "channel_id" => "C1",
                 "channel_name" => "fleet",
                 "events" => []
               })

      assert %{events: ["choose at least one event"]} = errors_on(changeset)

      subscription_fixture(context)

      assert {:error, changeset} =
               Subscriptions.create_subscription(context.scope, context.connection, %{
                 "channel_id" => "C0FLEET",
                 "channel_name" => "fleet",
                 "events" => ["device.health_status_changed"]
               })

      assert %{connection_id: ["already gets this organization's events"]} = errors_on(changeset)
    end

    test "stops at the per-organization limit", context do
      for n <- 1..Subscriptions.max_subscriptions_per_org(),
          do: subscription_fixture(context, %{"channel_id" => "C#{n}"})

      assert {:error, :too_many_subscriptions} =
               Subscriptions.create_subscription(context.scope, context.connection, %{
                 "channel_id" => "C0",
                 "channel_name" => "one-more",
                 "events" => ["device.health_status_changed"]
               })
    end
  end

  describe "events reaching a channel" do
    test "a device event is held, and one job is queued however many follow", context do
      subscription = subscription_fixture(context)

      health_change(context.product.id, "nh-1")
      health_change(context.product.id, "nh-2")

      assert [%PendingEvent{type: "device.health_status_changed", data: data}, _] = Repo.all(PendingEvent)
      assert %{"device" => %{"identifier" => "nh-1"}, "product" => %{"name" => "thermostat"}} = data

      assert [job] = all_enqueued(worker: PostSlackEvents)
      assert job.args == %{"subscription_id" => subscription.id}
      assert DateTime.diff(job.scheduled_at, DateTime.utc_now()) in 10..15
    end

    test "a subscription that is off, or limited to other products, hears nothing", %{user: user, org: org} = context do
      other = Fixtures.product_fixture(user, org, %{name: "doorbell"})
      limited = subscription_fixture(context, %{"products" => ["doorbell"]})
      off = subscription_fixture(context, %{"channel_id" => "C2"})
      {:ok, _} = Subscriptions.update_subscription(context.scope, off, %{"enabled" => false})

      health_change(context.product.id, "nh-1")
      assert Repo.all(PendingEvent) == []

      health_change(other.id, "nh-2")
      assert [%PendingEvent{subscription_id: subscription_id}] = Repo.all(PendingEvent)
      assert subscription_id == limited.id
    end

    test "a finished update goes to the channels for its outcome", context do
      failures = subscription_fixture(context, %{"events" => ["device.firmware_update.failed"]})

      successes =
        subscription_fixture(context, %{"channel_id" => "C2", "events" => ["device.firmware_update.succeeded"]})

      for outcome <- ["failed", "succeeded", "ignored"] do
        :ok =
          Integrations.dispatch(context.product.id, "device.firmware_update.finished", fn ->
            %{device: %{identifier: "nh-1"}, outcome: outcome}
          end)
      end

      assert [failed, succeeded] = PendingEvent |> order_by(:id) |> Repo.all()
      assert {failed.subscription_id, failed.type} == {failures.id, "device.firmware_update.failed"}
      assert {succeeded.subscription_id, succeeded.type} == {successes.id, "device.firmware_update.succeeded"}
    end

    test "a new product notification is posted once, however often it recurs", context do
      subscription_fixture(context, %{"events" => ["product.notification_created"]})

      for _ <- 1..3 do
        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          context.product.id,
          "nh-1",
          "x509"
        )
      end

      assert [%PendingEvent{type: "product.notification_created", data: %{"notification" => %{"title" => title}}}] =
               Repo.all(PendingEvent)

      assert is_binary(title)
    end

    test "a channel added now hears the next event", context do
      health_change(context.product.id, "nh-1")
      subscription_fixture(context)
      health_change(context.product.id, "nh-2")

      assert [%PendingEvent{data: %{"device" => %{"identifier" => "nh-2"}}}] = Repo.all(PendingEvent)
    end
  end

  describe "post_pending_events/1" do
    test "posts what is held as one message per kind of event, and forgets it", context do
      subscription =
        subscription_fixture(context, %{"events" => ["device.health_status_changed", "device.firmware_update.failed"]})

      stub_slack(%{"chat.postMessage" => %{"ok" => true}})

      health_change(context.product.id, "nh-1")
      health_change(context.product.id, "nh-2", "warning")

      :ok =
        Integrations.dispatch(context.product.id, "device.firmware_update.finished", fn ->
          %{device: %{identifier: "nh-3"}, outcome: "failed", target_firmware: %{version: "1.0"}}
        end)

      assert :ok = Subscriptions.post_pending_events(subscription.id)

      assert_received {:slack, "chat.postMessage", health}
      assert_received {:slack, "chat.postMessage", update}
      refute_received {:slack, "chat.postMessage", _}

      assert %{"channel" => "C0FLEET", "text" => "2 devices changed health status: 1 unhealthy, 1 warning"} =
               Jason.decode!(health)

      assert %{"text" => "Update to 1.0 failed on nh-3"} = Jason.decode!(update)
      assert Repo.all(PendingEvent) == []
    end

    test "waits as long as Slack asks", context do
      subscription = subscription_fixture(context)
      stub_slack(%{"chat.postMessage" => {429, [{"retry-after", "12"}], %{"ok" => false, "error" => "ratelimited"}}})

      health_change(context.product.id, "nh-1")

      assert {:rate_limited, 12} = Subscriptions.post_pending_events(subscription.id)
      assert [_held] = Repo.all(PendingEvent)
    end

    test "turns the subscription off when the channel cannot be posted to, and says so", context do
      subscription = subscription_fixture(context)
      stub_slack(%{"chat.postMessage" => %{"ok" => false, "error" => "is_archived"}})

      health_change(context.product.id, "nh-1")

      assert {:cancel, "turned off because the channel was archived"} =
               Subscriptions.post_pending_events(subscription.id)

      assert %Subscription{enabled: false, disabled_reason: "Turned off because the channel was archived."} =
               Repo.reload!(subscription)

      assert Repo.all(PendingEvent) == []

      assert [%Notification{title: "Slack notifications were turned off.", product_id: product_id}] =
               Repo.all(Notification)

      assert product_id == context.product.id

      health_change(context.product.id, "nh-2")
      assert Repo.all(PendingEvent) == []
    end

    test "records any other failure, to try again", context do
      subscription = subscription_fixture(context)
      stub_slack(%{"chat.postMessage" => %{"ok" => false, "error" => "internal_error"}})
      health_change(context.product.id, "nh-1")

      assert {:error, "internal_error"} = Subscriptions.post_pending_events(subscription.id)
      assert %Subscription{enabled: true, last_error: "internal_error"} = Repo.reload!(subscription)
      assert [_held] = Repo.all(PendingEvent)

      stub_slack(%{"chat.postMessage" => %{"ok" => true}})
      assert :ok = Subscriptions.post_pending_events(subscription.id)
      assert %Subscription{last_error: nil} = Repo.reload!(subscription)
    end

    test "drops events held for more than an hour", context do
      subscription = subscription_fixture(context)
      stub_slack(%{"chat.postMessage" => %{"ok" => true}})
      health_change(context.product.id, "nh-1")

      {1, _} = Repo.update_all(PendingEvent, set: [inserted_at: DateTime.add(DateTime.utc_now(), -2, :hour)])

      assert :ok = Subscriptions.post_pending_events(subscription.id)
      refute_received {:slack, "chat.postMessage", _}
      assert Repo.all(PendingEvent) == []
    end

    test "cancels, dropping what is held, for a subscription since deleted", context do
      subscription = subscription_fixture(context)
      health_change(context.product.id, "nh-1")
      {:ok, _} = Subscriptions.delete_subscription(context.scope, subscription)

      assert {:cancel, _} = Subscriptions.post_pending_events(subscription.id)
    end
  end

  describe "the worker" do
    test "snoozes while Slack asks it to wait, and cancels a turned off subscription", context do
      subscription = subscription_fixture(context)
      health_change(context.product.id, "nh-1")

      stub_slack(%{"chat.postMessage" => {429, [{"retry-after", "7"}], %{"ok" => false, "error" => "ratelimited"}}})
      assert {:snooze, 7} = perform_job(PostSlackEvents, %{subscription_id: subscription.id})

      stub_slack(%{"chat.postMessage" => %{"ok" => false, "error" => "channel_not_found"}})
      assert {:cancel, _} = perform_job(PostSlackEvents, %{subscription_id: subscription.id})
    end

    test "gives up after three retries", context do
      subscription = subscription_fixture(context)
      health_change(context.product.id, "nh-1")
      stub_slack(%{"chat.postMessage" => %{"ok" => false, "error" => "fatal_error"}})

      assert {:snooze, 10} = perform_job(PostSlackEvents, %{subscription_id: subscription.id})
      assert {:snooze, 300} = perform_job(PostSlackEvents, %{subscription_id: subscription.id}, meta: %{"snoozed" => 2})

      assert {:cancel, "gave up after 4 attempts: fatal_error"} =
               perform_job(PostSlackEvents, %{subscription_id: subscription.id}, meta: %{"snoozed" => 3})
    end
  end

  test "send_test_message/2 posts what the channel will get", context do
    subscription = subscription_fixture(context, %{"events" => ["device.firmware_update.failed"]})
    stub_slack(%{"chat.postMessage" => %{"ok" => true}})

    assert :ok = Subscriptions.send_test_message(context.scope, subscription)

    assert_received {:slack, "chat.postMessage", body}
    assert %{"channel" => "C0FLEET", "text" => text} = Jason.decode!(body)
    assert text =~ "NervesHub will post Update failed"
  end

  test "disconnecting the workspace stops the events", context do
    subscription_fixture(context)
    stub_slack(%{"auth.revoke" => %{"ok" => true}})

    :ok = Slack.disconnect(context.scope, context.connection)
    health_change(context.product.id, "nh-1")

    assert Repo.all(PendingEvent) == []
  end
end
