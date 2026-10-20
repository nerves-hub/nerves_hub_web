defmodule NervesHub.Integrations.ChatWebhooksTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.Integrations
  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Integrations.ChatWebhooks.ChatWebhook
  alias NervesHub.Integrations.ChatWebhooks.PendingEvent
  alias NervesHub.Products.Notification
  alias NervesHub.Workers.PostChatWebhookEvents

  @url "https://prod-07.westeurope.logic.azure.com:443/workflows/1f2e/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=c2lnbmF0dXJl"

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org, %{name: "thermostat"})

    %{org: org, product: product, scope: %Scope{org: org, user: user, role: :admin}, user: user}
  end

  defp channel_fixture(%{scope: scope}, attrs \\ %{}) do
    attrs = Map.merge(%{"name" => "Fleet alerts", "url" => @url, "events" => ["device.health_status_changed"]}, attrs)
    {:ok, channel} = ChatWebhooks.create_channel(scope, :teams, attrs)
    channel
  end

  # Answers every post with `status`, and tells the test what was posted.
  defp stub_webhook(status, headers \\ []) do
    test_pid = self()

    Req.Test.stub(ChatWebhooks, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:posted, conn.host, Jason.decode!(body)})

      conn
      |> Plug.Conn.merge_resp_headers(headers)
      |> Plug.Conn.send_resp(status, "")
    end)
  end

  defp health_change(product_id, identifier, status \\ "unhealthy") do
    :ok =
      Integrations.dispatch(product_id, "device.health_status_changed", fn ->
        %{device: %{identifier: identifier}, status: status, previous_status: "healthy", reasons: nil}
      end)
  end

  defp texts(%{"attachments" => [%{"content" => %{"body" => body}}]}) do
    for %{"inlines" => inlines} <- body, do: Enum.map_join(inlines, & &1["text"])
  end

  describe "create_channel/2" do
    test "keeps the webhook's URL encrypted, and audits where it points", %{org: org, scope: scope} do
      channel = channel_fixture(%{scope: scope})

      assert channel.url == @url
      assert channel.url_host == "prod-07.westeurope.logic.azure.com"

      [stored] = Repo.query!("SELECT url FROM chat_webhooks").rows |> List.flatten() |> List.wrap()
      refute stored =~ "logic.azure.com"

      assert [log] = AuditLogs.logs_for(org)

      assert log.description =~
               "started posting Health status changed from every product to Microsoft Teams channel Fleet alerts"

      assert log.description =~ "prod-07.westeurope.logic.azure.com"
      refute log.description =~ "sig="
    end

    test "takes only a Workflows webhook's URL", %{scope: scope} do
      for {url, message} <- [
            {"https://example.com/hook", "must be the URL Teams gives a Workflows webhook"},
            {"http://prod-07.westeurope.logic.azure.com/workflows/1", "must start with https://"},
            {"https://acme.webhook.office.com/webhookb2/abc", "is an Office 365 connector URL"},
            {"not a url", "is not a valid URL"}
          ] do
        assert {:error, changeset} =
                 ChatWebhooks.create_channel(scope, :teams, %{
                   "name" => "Fleet",
                   "url" => url,
                   "events" => ["device.health_status_changed"]
                 })

        assert [error] = errors_on(changeset).url
        assert error =~ message
      end

      newer =
        "https://default1a2b.04.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/9f/triggers/manual/paths/invoke?api-version=1&sig=abc"

      assert {:ok, _} =
               ChatWebhooks.create_channel(scope, :teams, %{
                 "name" => "Newer",
                 "url" => newer,
                 "events" => ["device.health_status_changed"]
               })
    end

    test "needs a name, a URL and an event", %{scope: scope} do
      assert {:error, changeset} = ChatWebhooks.create_channel(scope, :teams, %{"events" => []})
      assert %{name: [_], url: [_], events: ["choose at least one event"]} = errors_on(changeset)
    end

    test "stops at the per-organization limit", %{scope: scope} = context do
      for n <- 1..ChatWebhooks.max_channels_per_org(), do: channel_fixture(context, %{"name" => "Channel #{n}"})

      assert {:error, :too_many_channels} =
               ChatWebhooks.create_channel(scope, :teams, %{
                 "name" => "One more",
                 "url" => @url,
                 "events" => ["device.health_status_changed"]
               })
    end
  end

  describe "update_channel/3" do
    test "keeps the URL unless a new one is given", %{scope: scope} = context do
      channel = channel_fixture(context)

      {:ok, renamed} = ChatWebhooks.update_channel(scope, channel, %{"name" => "Renamed", "url" => ""})
      assert renamed.url == @url

      newer = String.replace(@url, "prod-07", "prod-08")
      {:ok, replaced} = ChatWebhooks.update_channel(scope, renamed, %{"url" => newer})
      assert replaced.url == newer
      assert replaced.url_host == "prod-08.westeurope.logic.azure.com"

      assert [log | _] = AuditLogs.logs_for(context.org)
      assert log.description =~ "with a new webhook on prod-08.westeurope.logic.azure.com"
    end
  end

  describe "events reaching a channel" do
    test "an event is held, and one job is queued however many follow", context do
      channel = channel_fixture(context)

      health_change(context.product.id, "nh-1")
      health_change(context.product.id, "nh-2")

      assert [_, _] = Repo.all(PendingEvent)
      assert [_job] = all_enqueued(worker: PostChatWebhookEvents, args: %{chat_webhook_id: channel.id})
    end

    test "a channel that is off, or limited to other products, hears nothing", %{user: user, org: org} = context do
      off = channel_fixture(context)
      {:ok, _} = ChatWebhooks.update_channel(context.scope, off, %{"enabled" => false})

      other = Fixtures.product_fixture(user, org, %{name: "kettle"})
      _limited = channel_fixture(context, %{"name" => "Kettles", "all_products" => "false", "products" => ["kettle"]})

      health_change(context.product.id, "nh-1")
      assert Repo.all(PendingEvent) == []

      health_change(other.id, "nh-2")
      assert [%PendingEvent{}] = Repo.all(PendingEvent)
    end
  end

  describe "post_pending_events/1" do
    test "posts what is held as one card per kind of event, and forgets it", context do
      channel =
        channel_fixture(context, %{"events" => ["device.health_status_changed", "device.firmware_update.failed"]})

      stub_webhook(202)

      health_change(context.product.id, "nh-1")
      health_change(context.product.id, "nh-2", "warning")

      :ok =
        Integrations.dispatch(context.product.id, "device.firmware_update.finished", fn ->
          %{device: %{identifier: "nh-3"}, outcome: "failed", target_firmware: %{version: "1.0"}}
        end)

      assert :ok = ChatWebhooks.post_pending_events(channel.id)

      assert_received {:posted, "prod-07.westeurope.logic.azure.com", health}
      assert_received {:posted, _host, update}
      refute_received {:posted, _host, _}

      assert ["2 devices changed health status: 1 unhealthy, 1 warning" | _] = texts(health)
      assert ["❌ Update to 1.0 failed on nh-3" | _] = texts(update)
      assert Repo.all(PendingEvent) == []
    end

    test "waits as long as Power Automate asks", context do
      channel = channel_fixture(context)
      stub_webhook(429, [{"retry-after", "12"}])
      health_change(context.product.id, "nh-1")

      assert {:rate_limited, 12} = ChatWebhooks.post_pending_events(channel.id)
      assert [_held] = Repo.all(PendingEvent)
    end

    test "turns the channel off when the chat service refuses the webhook, and says so", context do
      channel = channel_fixture(context)
      stub_webhook(404)
      health_change(context.product.id, "nh-1")

      assert {:cancel, "turned off because Microsoft Teams refused the webhook (HTTP 404)" <> _} =
               ChatWebhooks.post_pending_events(channel.id)

      assert %ChatWebhook{
               enabled: false,
               disabled_reason: "Turned off because Microsoft Teams refused the webhook (HTTP 404)" <> _
             } =
               Repo.reload!(channel)

      assert Repo.all(PendingEvent) == []

      assert [%Notification{title: "Microsoft Teams notifications were turned off.", product_id: product_id}] =
               Repo.all(Notification)

      assert product_id == context.product.id

      # Turning it back on is a person saying the workflow is fixed.
      {:ok, on_again} = ChatWebhooks.update_channel(context.scope, Repo.reload!(channel), %{"enabled" => true})
      assert %ChatWebhook{enabled: true, disabled_reason: nil} = on_again
    end

    test "a new URL turns back on a channel posting turned off, but not one a person did", context do
      channel = channel_fixture(context)
      stub_webhook(404)
      health_change(context.product.id, "nh-1")
      {:cancel, _} = ChatWebhooks.post_pending_events(channel.id)

      newer = String.replace(@url, "prod-07", "prod-08")
      {:ok, fixed} = ChatWebhooks.update_channel(context.scope, Repo.reload!(channel), %{"url" => newer})
      assert %ChatWebhook{enabled: true, disabled_reason: nil} = fixed

      {:ok, off} = ChatWebhooks.update_channel(context.scope, fixed, %{"enabled" => false})
      {:ok, still_off} = ChatWebhooks.update_channel(context.scope, off, %{"url" => @url})
      assert %ChatWebhook{enabled: false} = still_off
    end

    test "records any other failure, to try again", context do
      channel = channel_fixture(context)
      stub_webhook(502)
      health_change(context.product.id, "nh-1")

      assert {:error, "HTTP 502"} = ChatWebhooks.post_pending_events(channel.id)
      assert %ChatWebhook{enabled: true, last_error: "HTTP 502"} = Repo.reload!(channel)
      assert [_held] = Repo.all(PendingEvent)

      stub_webhook(202)
      assert :ok = ChatWebhooks.post_pending_events(channel.id)
      assert %ChatWebhook{last_error: nil} = Repo.reload!(channel)
    end

    test "drops events held for more than an hour", context do
      channel = channel_fixture(context)
      stub_webhook(202)
      health_change(context.product.id, "nh-1")

      {1, _} = Repo.update_all(PendingEvent, set: [inserted_at: DateTime.add(DateTime.utc_now(), -2, :hour)])

      assert :ok = ChatWebhooks.post_pending_events(channel.id)
      refute_received {:posted, _, _}
    end

    test "cancels, dropping what is held, for a channel since deleted", context do
      channel = channel_fixture(context)
      health_change(context.product.id, "nh-1")
      {:ok, _} = ChatWebhooks.delete_channel(context.scope, channel)

      assert {:cancel, _} = ChatWebhooks.post_pending_events(channel.id)
    end
  end

  describe "queue_stranded/0" do
    test "queues a job for events none is coming for, unless one is waiting or running", context do
      channel = channel_fixture(context)
      health_change(context.product.id, "nh-1")
      {1, _} = Repo.update_all(PendingEvent, set: [inserted_at: DateTime.add(DateTime.utc_now(), -1, :minute)])

      assert ChatWebhooks.queue_stranded() == 0

      {1, _} = Repo.update_all(Oban.Job, set: [state: "executing"])
      assert ChatWebhooks.queue_stranded() == 0

      # The job ran before the event was there to see, or gave up.
      {1, _} = Repo.update_all(Oban.Job, set: [state: "completed"])
      assert ChatWebhooks.queue_stranded() == 1

      assert [job] = all_enqueued(worker: PostChatWebhookEvents)
      assert job.args == %{"chat_webhook_id" => channel.id}
    end
  end

  describe "the worker" do
    test "snoozes while Power Automate asks it to wait, and cancels a refused webhook", context do
      channel = channel_fixture(context)
      health_change(context.product.id, "nh-1")

      stub_webhook(429, [{"retry-after", "7"}])
      assert {:snooze, 7} = perform_job(PostChatWebhookEvents, %{chat_webhook_id: channel.id})

      stub_webhook(403)
      assert {:cancel, _} = perform_job(PostChatWebhookEvents, %{chat_webhook_id: channel.id})
    end
  end

  test "send_test_message/2 posts what the channel will get", context do
    channel = channel_fixture(context, %{"events" => ["device.firmware_update.failed"]})
    stub_webhook(202)

    assert :ok = ChatWebhooks.send_test_message(context.scope, channel)

    assert_received {:posted, _host, message}
    assert [text] = texts(message)
    assert text =~ "NervesHub will post Update failed"
  end

  describe "Discord" do
    @discord_url "https://discord.com/api/webhooks/123456789012345678/AbC-dEf_GhI"

    defp discord_fixture(%{scope: scope}, attrs \\ %{}) do
      attrs =
        Map.merge(%{"name" => "#fleet", "url" => @discord_url, "events" => ["device.health_status_changed"]}, attrs)

      {:ok, channel} = ChatWebhooks.create_channel(scope, :discord, attrs)
      channel
    end

    test "takes only a Discord channel webhook's URL", %{scope: scope} do
      for {url, message} <- [
            {"https://discord.com/channels/1/2", "must be the URL Discord gives a channel webhook"},
            {"https://evil.example.com/api/webhooks/1/abc", "must be the URL Discord gives a channel webhook"},
            {"http://discord.com/api/webhooks/1/abc", "must start with https://"},
            {@url, "must be the URL Discord gives a channel webhook"}
          ] do
        assert {:error, changeset} =
                 ChatWebhooks.create_channel(scope, :discord, %{
                   "name" => "#fleet",
                   "url" => url,
                   "events" => ["device.health_status_changed"]
                 })

        assert [^message] = errors_on(changeset).url
      end

      for url <- [
            "https://discordapp.com/api/webhooks/1/abc",
            "https://discord.com/api/v10/webhooks/1/abc"
          ] do
        assert {:ok, %ChatWebhook{provider: :discord}} =
                 ChatWebhooks.create_channel(scope, :discord, %{
                   "name" => "#fleet",
                   "url" => url,
                   "events" => ["device.health_status_changed"]
                 })
      end
    end

    test "each chat service has its own channels, and its own limit", context do
      teams = channel_fixture(context)
      discord = discord_fixture(context)

      assert [%{id: teams_id}] = ChatWebhooks.list_channels(context.org, :teams)
      assert [%{id: discord_id}] = ChatWebhooks.list_channels(context.org, :discord)
      assert {teams_id, discord_id} == {teams.id, discord.id}

      for n <- 2..ChatWebhooks.max_channels_per_org(), do: channel_fixture(context, %{"name" => "Channel #{n}"})

      assert {:ok, _} =
               ChatWebhooks.create_channel(context.scope, :discord, %{
                 "name" => "#more",
                 "url" => @discord_url,
                 "events" => ["device.health_status_changed"]
               })
    end

    test "posts embeds under the instance's name, mentioning nobody", context do
      channel = discord_fixture(context)
      stub_webhook(204)

      health_change(context.product.id, "nh-1")
      assert :ok = ChatWebhooks.post_pending_events(channel.id)

      assert_received {:posted, "discord.com", body}

      assert %{
               "username" => "NervesHub",
               "allowed_mentions" => %{"parse" => []},
               "embeds" => [%{"title" => "🔴 nh-1 is now unhealthy"}]
             } = body
    end

    test "a webhook Discord refuses turns the channel off, and says so", context do
      channel = discord_fixture(context)
      stub_webhook(404)
      health_change(context.product.id, "nh-1")

      assert {:cancel, "turned off because Discord refused the webhook (HTTP 404)" <> _} =
               ChatWebhooks.post_pending_events(channel.id)

      assert [%Notification{title: "Discord notifications were turned off."}] = Repo.all(Notification)

      assert [log | _] = AuditLogs.logs_for(context.org)
      assert log.description =~ "Discord channel #fleet"
    end
  end
end
