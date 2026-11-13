defmodule NervesHub.Workers.QueueStrandedChatEventsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHub.Integrations
  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Integrations.Slack.PendingEvent
  alias NervesHub.Integrations.Slack.Subscriptions
  alias NervesHub.Workers.PostChatWebhookEvents
  alias NervesHub.Workers.PostSlackEvents
  alias NervesHub.Workers.QueueStrandedChatEvents

  @teams_url "https://prod-07.westeurope.logic.azure.com:443/workflows/1f2e/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=c2lnbmF0dXJl"

  test "queues a job for Slack and chat webhook events none is coming for" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    scope = %Scope{org: org, user: user, role: :admin}
    events = ["device.health_status_changed"]

    {:ok, subscription} =
      Subscriptions.create_subscription(scope, Fixtures.slack_connection_fixture(org, user), %{
        "channel_id" => "C0FLEET",
        "channel_name" => "fleet",
        "events" => events
      })

    {:ok, channel} =
      ChatWebhooks.create_channel(scope, :teams, %{"name" => "Fleet alerts", "url" => @teams_url, "events" => events})

    :ok =
      Integrations.dispatch(product.id, "device.health_status_changed", fn ->
        %{device: %{identifier: "nh-1"}, status: "unhealthy", previous_status: "healthy", reasons: nil}
      end)

    # Both channels' jobs ran before the event was there for them to see.
    {2, _} = Repo.update_all(Oban.Job, set: [state: "completed"])
    held_since = DateTime.add(DateTime.utc_now(), -1, :minute)
    {1, _} = Repo.update_all(PendingEvent, set: [inserted_at: held_since])
    {1, _} = Repo.update_all(NervesHub.Integrations.ChatWebhooks.PendingEvent, set: [inserted_at: held_since])

    assert :ok = perform_job(QueueStrandedChatEvents, %{})

    assert_enqueued(worker: PostSlackEvents, args: %{subscription_id: subscription.id})
    assert_enqueued(worker: PostChatWebhookEvents, args: %{chat_webhook_id: channel.id})
  end
end
