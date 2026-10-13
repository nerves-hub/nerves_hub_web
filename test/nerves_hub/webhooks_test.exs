defmodule NervesHub.WebhooksTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.Products.Notification
  alias NervesHub.Webhooks
  alias NervesHub.Webhooks.Webhook
  alias NervesHub.Workers.DeliverWebhook

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    scope = %Scope{org: org, product: product, user: user}

    %{org: org, product: product, scope: scope, user: user}
  end

  defp webhook_fixture(scope, attrs \\ %{}) do
    attrs = Map.merge(%{"url" => "https://example.com/hooks", "events" => ["device.connected"]}, attrs)
    {:ok, webhook} = Webhooks.create_webhook(scope, attrs)
    webhook
  end

  describe "create_webhook/2" do
    test "creates an enabled webhook with a generated signing secret, and audits it", %{
      product: product,
      scope: scope
    } do
      assert {:ok, webhook} =
               Webhooks.create_webhook(scope, %{
                 "url" => " https://example.com/hooks ",
                 "description" => "Fleet dashboard",
                 "events" => ["device.connected", "device.disconnected", "device.connected"]
               })

      assert webhook.url == "https://example.com/hooks"
      assert webhook.enabled
      assert webhook.events == ["device.connected", "device.disconnected"]
      assert "whsec_" <> _ = webhook.secret

      assert [log] = AuditLogs.logs_for(product)
      assert log.description =~ "added webhook #{webhook.id}"
      assert log.description =~ "example.com"
    end

    test "never puts the URL in the audit log", %{product: product, scope: scope} do
      webhook_fixture(scope, %{"url" => "https://hooks.example.com/services/T000/B000/sekrit"})

      assert [log] = AuditLogs.logs_for(product)
      refute log.description =~ "sekrit"
    end

    test "requires a valid URL and at least one known event", %{scope: scope} do
      assert {:error, changeset} = Webhooks.create_webhook(scope, %{"url" => "ftp://example.com", "events" => []})

      assert %{url: ["must start with https:// or http://"], events: ["choose at least one event"]} =
               errors_on(changeset)

      assert {:error, changeset} =
               Webhooks.create_webhook(scope, %{"url" => "https://example.com", "events" => ["device.exploded"]})

      assert %{events: ["contains an event that does not exist"]} = errors_on(changeset)
    end

    test "stops at the per-product limit", %{scope: scope} do
      for _ <- 1..Webhooks.max_webhooks_per_product(), do: webhook_fixture(scope)

      assert {:error, :too_many_webhooks} =
               Webhooks.create_webhook(scope, %{"url" => "https://example.com", "events" => ["device.connected"]})
    end
  end

  describe "update_webhook/3" do
    test "turning a webhook back on clears what deliveries recorded", %{scope: scope} do
      webhook = webhook_fixture(scope)

      webhook =
        webhook
        |> Ecto.Changeset.change(
          enabled: false,
          disabled_reason: "Turned off because it broke.",
          failing_since: DateTime.utc_now(:second),
          last_error: "HTTP 500",
          last_error_at: DateTime.utc_now(:second)
        )
        |> Repo.update!()

      assert {:ok, webhook} = Webhooks.update_webhook(scope, webhook, %{"enabled" => true})

      assert %Webhook{enabled: true, disabled_reason: nil, failing_since: nil, last_error: nil} = webhook
    end
  end

  describe "regenerate_secret/2" do
    test "replaces the secret", %{scope: scope} do
      webhook = webhook_fixture(scope)

      assert {:ok, updated} = Webhooks.regenerate_secret(scope, webhook)
      refute updated.secret == webhook.secret
    end
  end

  describe "dispatch/3" do
    test "queues nothing, and builds nothing, when no webhook subscribes", %{product: product, scope: scope} do
      Webhooks.dispatch(product.id, "device.connected", fn -> flunk("built data with no subscriber") end)

      webhook_fixture(scope, %{"events" => ["device.disconnected"]})

      Webhooks.dispatch(product.id, "device.connected", fn -> flunk("built data with no subscriber") end)

      refute_enqueued(worker: DeliverWebhook)
    end

    test "queues one delivery per subscribed webhook, sharing the event's id and body", %{
      org: org,
      product: product,
      scope: scope
    } do
      first = webhook_fixture(scope)
      second = webhook_fixture(scope, %{"events" => ["device.connected", "device.disconnected"]})
      _other = webhook_fixture(scope, %{"events" => ["device.disconnected"]})

      :ok = Webhooks.dispatch(product.id, "device.connected", fn -> %{device: %{identifier: "abc123"}} end)

      jobs = all_enqueued(worker: DeliverWebhook)
      assert jobs |> Enum.map(& &1.args["webhook_id"]) |> Enum.sort() == Enum.sort([first.id, second.id])

      assert [%{"event_id" => "msg_" <> _ = event_id, "body" => body}] =
               jobs |> Enum.map(& &1.args) |> Enum.uniq_by(& &1["body"])

      assert Enum.all?(jobs, &(&1.args["event_id"] == event_id))

      assert %{
               "type" => "device.connected",
               "timestamp" => timestamp,
               "data" => %{
                 "device" => %{"identifier" => "abc123"},
                 "org" => %{"name" => org_name},
                 "product" => %{"name" => product_name}
               }
             } = Jason.decode!(body)

      assert {:ok, _, 0} = DateTime.from_iso8601(timestamp)
      assert org_name == org.name
      assert product_name == product.name
    end

    test "sees a webhook as soon as it is created, despite the cache", %{product: product, scope: scope} do
      :ok = Webhooks.dispatch(product.id, "device.connected", fn -> %{} end)
      refute_enqueued(worker: DeliverWebhook)

      webhook = webhook_fixture(scope)
      :ok = Webhooks.dispatch(product.id, "device.connected", fn -> %{} end)

      assert_enqueued(worker: DeliverWebhook, args: %{webhook_id: webhook.id})
    end

    test "skips webhooks that are turned off", %{product: product, scope: scope} do
      webhook = webhook_fixture(scope)
      {:ok, _} = Webhooks.update_webhook(scope, webhook, %{"enabled" => false})

      :ok = Webhooks.dispatch(product.id, "device.connected", fn -> %{} end)

      refute_enqueued(worker: DeliverWebhook)
    end

    test "makes device-supplied text safe to store", %{product: product, scope: scope} do
      webhook_fixture(scope)

      :ok =
        Webhooks.dispatch(product.id, "device.connected", fn ->
          %{reason: "bad\0byte " <> <<0xFF>>, nested: %{<<0xFE>> => ["ok", <<0>>]}}
        end)

      assert [job] = all_enqueued(worker: DeliverWebhook)
      assert %{"data" => %{"reason" => reason, "nested" => nested}} = Jason.decode!(job.args["body"])
      assert reason == "badbyte �"
      assert nested == %{"�" => ["ok", ""]}
    end

    test "drops an event too large to queue", %{product: product, scope: scope} do
      webhook_fixture(scope)

      :ok = Webhooks.dispatch(product.id, "device.connected", fn -> %{blob: String.duplicate("a", 300_000)} end)

      refute_enqueued(worker: DeliverWebhook)
    end

    test "ignores events with no product" do
      assert :ok = Webhooks.dispatch(nil, "device.connected", fn -> flunk("built data with no product") end)
    end
  end

  describe "deliverable_webhook/1" do
    test "is nil for a webhook that is off, or whose product was deleted", %{product: product, scope: scope} do
      webhook = webhook_fixture(scope)
      assert %Webhook{} = Webhooks.deliverable_webhook(webhook.id)

      {:ok, off} = Webhooks.update_webhook(scope, webhook, %{"enabled" => false})
      assert is_nil(Webhooks.deliverable_webhook(off.id))

      {:ok, on} = Webhooks.update_webhook(scope, off, %{"enabled" => true})
      {:ok, _} = NervesHub.Products.delete_product(product)
      assert is_nil(Webhooks.deliverable_webhook(on.id))
    end
  end

  describe "record_failure/3 and record_success/1" do
    test "a failure marks the webhook failing, and a success clears it", %{scope: scope} do
      webhook = webhook_fixture(scope)

      assert :ok = Webhooks.record_failure(webhook, 500, "HTTP 500")

      webhook = Repo.reload!(webhook)
      assert webhook.failing_since
      assert webhook.last_error == "HTTP 500"
      assert webhook.last_error_at

      assert :ok = Webhooks.record_success(webhook)
      assert %Webhook{failing_since: nil, last_error: "HTTP 500"} = Repo.reload!(webhook)
    end

    test "writes failures at most every 30 seconds", %{scope: scope} do
      webhook = webhook_fixture(scope)

      :ok = Webhooks.record_failure(webhook, 500, "HTTP 500")
      :ok = Webhooks.record_failure(webhook, 502, "HTTP 502")

      assert %Webhook{last_error: "HTTP 500"} = Repo.reload!(webhook)
    end

    test "turns the webhook off once it has failed for a day, and says so", %{product: product, scope: scope} do
      webhook = webhook_fixture(scope)
      day_ago = DateTime.add(DateTime.utc_now(:second), -25, :hour)

      webhook =
        webhook
        |> Ecto.Changeset.change(failing_since: day_ago, last_error_at: day_ago)
        |> Repo.update!()

      assert :disabled = Webhooks.record_failure(webhook, 503, "HTTP 503")

      assert %Webhook{enabled: false, disabled_reason: reason} = Repo.reload!(webhook)
      assert reason =~ "24 hours"

      assert [%Notification{title: "A webhook was turned off."}] = Repo.all(Notification)

      :ok = Webhooks.dispatch(product.id, "device.connected", fn -> %{} end)
      refute_enqueued(worker: DeliverWebhook)
    end

    test "turns the webhook off when the endpoint answers 410 Gone", %{scope: scope} do
      webhook = webhook_fixture(scope)

      assert :disabled = Webhooks.record_failure(webhook, 410, "HTTP 410")

      assert %Webhook{enabled: false, disabled_reason: reason} = Repo.reload!(webhook)
      assert reason =~ "410 Gone"
    end
  end

  describe "cooling_down?/2" do
    test "only while failing, and only shortly after the last failure" do
      now = DateTime.utc_now(:second)

      refute Webhooks.cooling_down?(%Webhook{failing_since: nil, last_error_at: now}, now)
      assert Webhooks.cooling_down?(%Webhook{failing_since: now, last_error_at: now}, DateTime.add(now, 10))
      refute Webhooks.cooling_down?(%Webhook{failing_since: now, last_error_at: now}, DateTime.add(now, 31))
    end
  end
end
