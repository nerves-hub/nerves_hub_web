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
      org: org,
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
      assert webhook.all_products
      assert webhook.products == []
      assert "whsec_" <> _ = webhook.secret

      assert [log] = AuditLogs.logs_for(org)
      assert log.org_id == org.id
      assert log.description =~ "added webhook #{webhook.id}"
      assert log.description =~ "from every product"
      assert log.description =~ "example.com"
    end

    test "never puts the URL in the audit log", %{org: org, scope: scope} do
      webhook_fixture(scope, %{"url" => "https://hooks.example.com/services/T000/B000/sekrit"})

      assert [log] = AuditLogs.logs_for(org)
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

    test "stops at the per-organization limit", %{scope: scope} do
      for _ <- 1..Webhooks.max_webhooks_per_org(), do: webhook_fixture(scope)

      assert {:error, :too_many_webhooks} =
               Webhooks.create_webhook(scope, %{"url" => "https://example.com", "events" => ["device.connected"]})
    end
  end

  describe "products" do
    setup %{org: org, user: user} do
      %{other_product: Fixtures.product_fixture(user, org, %{name: "other"})}
    end

    test "limits a webhook to the products it names", %{org: org, other_product: other, product: product, scope: scope} do
      webhook = webhook_fixture(scope, %{"all_products" => false, "products" => [other.name]})

      assert %Webhook{all_products: false, products: [%{id: other_id}]} = webhook
      assert other_id == other.id

      :ok = Webhooks.dispatch(product.id, "device.connected", fn -> %{} end)
      refute_enqueued(worker: DeliverWebhook)

      :ok = Webhooks.dispatch(other.id, "device.connected", fn -> %{} end)
      assert_enqueued(worker: DeliverWebhook, args: %{webhook_id: webhook.id})

      assert [log] = AuditLogs.logs_for(org)
      assert log.description =~ "from product other"
    end

    test "naming products limits the webhook to them", %{other_product: other, scope: scope} do
      assert %Webhook{all_products: false, products: [%{name: "other"}]} =
               webhook_fixture(scope, %{"products" => [other.name]})
    end

    test "a webhook for every product hears products added later", %{org: org, scope: scope, user: user} do
      webhook = webhook_fixture(scope)
      later = Fixtures.product_fixture(user, org, %{name: "later"})

      :ok = Webhooks.dispatch(later.id, "device.connected", fn -> %{} end)

      assert_enqueued(worker: DeliverWebhook, args: %{webhook_id: webhook.id})
    end

    test "refuses a product of another organization", %{scope: scope, user: user} do
      other_org = Fixtures.org_fixture(user, %{name: "elsewhere"})
      theirs = Fixtures.product_fixture(user, other_org, %{name: "theirs"})

      assert {:error, changeset} =
               Webhooks.create_webhook(scope, %{
                 "url" => "https://example.com/hooks",
                 "events" => ["device.connected"],
                 "products" => [theirs.name]
               })

      assert %{products: ["has no product named theirs"]} = errors_on(changeset)

      :ok = Webhooks.dispatch(theirs.id, "device.connected", fn -> %{} end)
      refute_enqueued(worker: DeliverWebhook)
    end

    test "refuses a deleted product", %{other_product: other, scope: scope} do
      {:ok, _} = NervesHub.Products.delete_product(other)

      assert {:error, changeset} =
               Webhooks.create_webhook(scope, %{
                 "url" => "https://example.com/hooks",
                 "events" => ["device.connected"],
                 "products" => [other.name]
               })

      assert %{products: ["has no product named other"]} = errors_on(changeset)
    end

    test "needs a product unless it sends every product's events", %{scope: scope} do
      for products <- [[], nil] do
        attrs = %{"url" => "https://example.com/hooks", "events" => ["device.connected"], "all_products" => false}
        attrs = if products, do: Map.put(attrs, "products", products), else: attrs

        assert {:error, changeset} = Webhooks.create_webhook(scope, attrs)
        assert %{products: ["choose at least one product"]} = errors_on(changeset)
      end

      assert {:error, changeset} =
               Webhooks.create_webhook(scope, %{
                 "url" => "https://example.com/hooks",
                 "events" => ["device.connected"],
                 "products" => "thermostat"
               })

      assert %{products: ["must be a list of product names"]} = errors_on(changeset)
    end

    test "sending every product's events forgets the list", %{other_product: other, scope: scope} do
      webhook = webhook_fixture(scope, %{"products" => [other.name]})

      assert {:ok, %Webhook{all_products: true, products: []}} =
               Webhooks.update_webhook(scope, webhook, %{"all_products" => true})

      assert %Webhook{products: []} = scope.org |> Webhooks.get_webhook!(webhook.id)
    end

    test "a change of products reaches dispatching at once", %{
      other_product: other,
      product: product,
      scope: scope
    } do
      webhook = webhook_fixture(scope, %{"products" => [other.name]})

      # Caches that no webhook hears `product`.
      :ok = Webhooks.dispatch(product.id, "device.connected", fn -> %{} end)
      refute_enqueued(worker: DeliverWebhook)

      {:ok, _} = Webhooks.update_webhook(scope, webhook, %{"products" => [other.name, product.name]})

      :ok = Webhooks.dispatch(product.id, "device.connected", fn -> %{} end)
      assert_enqueued(worker: DeliverWebhook, args: %{webhook_id: webhook.id})
    end

    test "a change that names no products keeps them", %{other_product: other, scope: scope} do
      webhook = webhook_fixture(scope, %{"products" => [other.name]})

      assert {:ok, %Webhook{all_products: false, products: [%{name: "other"}]}} =
               Webhooks.update_webhook(scope, webhook, %{"events" => ["device.disconnected"]})
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
    test "is nil for a webhook that is off, or whose organization was deleted", %{org: org, scope: scope} do
      webhook = webhook_fixture(scope)
      assert %Webhook{} = Webhooks.deliverable_webhook(webhook.id)

      {:ok, off} = Webhooks.update_webhook(scope, webhook, %{"enabled" => false})
      assert is_nil(Webhooks.deliverable_webhook(off.id))

      {:ok, on} = Webhooks.update_webhook(scope, off, %{"enabled" => true})
      {:ok, _} = NervesHub.Accounts.soft_delete_org(org)
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

      assert [%Notification{title: "A webhook was turned off.", product_id: product_id}] = Repo.all(Notification)
      assert product_id == product.id

      :ok = Webhooks.dispatch(product.id, "device.connected", fn -> %{} end)
      refute_enqueued(worker: DeliverWebhook)
    end

    test "tells only the products the webhook was sending events for", %{org: org, scope: scope, user: user} do
      listed = Fixtures.product_fixture(user, org, %{name: "listed"})
      webhook = webhook_fixture(scope, %{"products" => [listed.name]})

      assert :disabled = Webhooks.record_failure(webhook, 410, "HTTP 410")

      assert [%Notification{product_id: product_id}] = Repo.all(Notification)
      assert product_id == listed.id
    end

    test "tells every product of a webhook for all of them", %{org: org, scope: scope, user: user} do
      second = Fixtures.product_fixture(user, org, %{name: "second"})
      webhook = webhook_fixture(scope)

      assert :disabled = Webhooks.record_failure(webhook, 410, "HTTP 410")

      notified = Notification |> Repo.all() |> Enum.map(& &1.product_id) |> Enum.sort()
      assert notified == Enum.sort([scope.product.id, second.id])
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
