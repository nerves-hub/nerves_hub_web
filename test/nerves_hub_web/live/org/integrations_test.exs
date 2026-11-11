defmodule NervesHubWeb.Live.Org.IntegrationsTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Subscriptions
  alias NervesHub.Repo
  alias NervesHub.Webhooks
  alias NervesHub.Webhooks.Signature
  alias NervesHub.Webhooks.Webhook

  defp webhook_fixture(%{org: org, user: user}, attrs \\ %{}) do
    scope = %Scope{org: org, user: user}

    attrs =
      Map.merge(%{"url" => "https://hooks.example.com/nerves?token=sekrit", "events" => ["device.connected"]}, attrs)

    {:ok, webhook} = Webhooks.create_webhook(scope, attrs)
    webhook
  end

  defp integrations_path(org), do: "/org/#{org.name}/settings/integrations"

  test "is a tab of the organization's page", %{conn: conn, org: org} do
    conn
    |> visit("/org/#{org.name}/settings/keys")
    |> click_link("Integrations")
    |> assert_path(integrations_path(org))
    |> assert_has("h2", text: "Integrations")
  end

  test "is no longer a tab of the product settings", %{conn: conn, org: org, product: product} do
    conn
    |> visit("/org/#{org.name}/#{product.name}/settings")
    |> refute_has("a", text: "Integrations")
  end

  test "offers one of each kind when there are none", %{conn: conn, org: org} do
    conn
    |> visit(integrations_path(org))
    |> assert_has("#integration-choices h3", text: "Slack")
    |> assert_has("#integration-choices h3", text: "Microsoft Teams")
    |> assert_has("#integration-choices h3", text: "Discord")
    |> assert_has("#integration-choices h3", text: "Webhook")
    |> refute_has("#add-integration-menu-toggle")
    |> refute_has("#chat-channels[role='table']")
    |> refute_has("#webhooks")
  end

  test "lists what can be added in the Add integration menu once there is one", context do
    %{conn: conn, org: org} = context
    webhook_fixture(context)

    conn
    |> visit(integrations_path(org))
    |> refute_has("#integration-choices")
    |> assert_has("h2 + span", text: "1")
    |> assert_has("#add-integration-menu button", text: "Microsoft Teams channel")
    |> assert_has("#add-integration-menu button", text: "Discord channel")
    |> assert_has("#add-integration-menu button", text: "Webhook")
    |> assert_has("#add-integration-menu button", text: "Connect a Slack workspace")
  end

  test "adds a webhook", %{conn: conn, org: org} do
    conn
    |> visit(integrations_path(org))
    |> click_button("Add webhook")
    |> assert_has("#webhook-dialog h2", text: "Add a webhook")
    |> unwrap(fn view ->
      view
      |> form("#webhook-form",
        webhook: %{
          url: "https://hooks.example.com/nerves",
          description: "Fleet dashboard",
          events: ["", "device.connected", "device.firmware_update.finished"]
        }
      )
      |> render_submit()
    end)
    |> assert_has("[role='alert']", text: "The webhook was added.")
    |> refute_has("#webhook-dialog")
    |> assert_has("#webhooks h3", text: "Fleet dashboard")
    |> assert_has("#webhooks code", text: "https://hooks.example.com/nerves")
    |> assert_has("#webhooks [role='cell']", text: "Every product")
    |> assert_has("#webhooks [role='cell']", text: "Device connected, Update finished")

    assert [
             %Webhook{
               events: ["device.connected", "device.firmware_update.finished"],
               all_products: true,
               enabled: true
             }
           ] = Webhooks.list_webhooks(org)
  end

  test "adds another webhook from the Add integration menu", context do
    %{conn: conn, org: org} = context
    webhook_fixture(context)

    conn
    |> visit(integrations_path(org))
    |> click_button("#add-webhook", "Webhook")
    |> unwrap(fn view ->
      view
      |> form("#webhook-form",
        webhook: %{url: "https://ingest.example.com/nerves", events: ["", "device.disconnected"]}
      )
      |> render_submit()
    end)
    |> assert_has("[role='alert']", text: "The webhook was added.")
    |> assert_has("h2 + span", text: "2")
    |> assert_has("#webhooks h3", text: "ingest.example.com")

    assert length(Webhooks.list_webhooks(org)) == 2
  end

  test "adds a webhook for some of the organization's products", context do
    %{conn: conn, org: org, product: product, user: user} = context
    _other = Fixtures.product_fixture(user, org, %{name: "other"})

    conn
    |> visit(integrations_path(org))
    |> click_button("Add webhook")
    |> unwrap(fn view ->
      view
      |> form("#webhook-form", webhook: %{all_products: "false"})
      |> render_change()

      view
      |> form("#webhook-form",
        webhook: %{
          url: "https://hooks.example.com/nerves",
          all_products: "false",
          products: ["", product.name],
          events: ["", "device.connected"]
        }
      )
      |> render_submit()
    end)
    |> assert_has("[role='alert']", text: "The webhook was added.")
    |> assert_has("#webhooks [role='cell'] span", text: product.name)

    assert [%Webhook{all_products: false, products: [%{name: name}]}] = Webhooks.list_webhooks(org)
    assert name == product.name
  end

  test "lists the products to choose from once the webhook is limited", context do
    %{conn: conn, org: org, product: product} = context

    conn
    |> visit(integrations_path(org))
    |> click_button("Add webhook")
    |> refute_has("#webhook-form label", text: product.name)
    |> unwrap(fn view ->
      view
      |> form("#webhook-form", webhook: %{all_products: "false"})
      |> render_change()
    end)
    |> assert_has("#webhook-form label", text: product.name)
  end

  test "needs a product when the webhook is limited", %{conn: conn, org: org} do
    conn
    |> visit(integrations_path(org))
    |> click_button("Add webhook")
    |> unwrap(fn view ->
      view
      |> form("#webhook-form",
        webhook: %{
          url: "https://hooks.example.com/nerves",
          all_products: "false",
          products: [""],
          events: ["", "device.connected"]
        }
      )
      |> render_submit()
    end)
    |> assert_has("#webhook-form", text: "choose at least one product")

    assert Webhooks.list_webhooks(org) == []
  end

  test "shows the products and events each webhook sends", context do
    %{conn: conn, org: org, product: product, user: user} = context
    _other = Fixtures.product_fixture(user, org, %{name: "other"})

    every =
      webhook_fixture(context, %{
        "events" => ["device.connected", "device.disconnected", "device.firmware_update.finished"]
      })

    some = webhook_fixture(context, %{"products" => [product.name, "other"]})

    conn
    |> visit(integrations_path(org))
    |> assert_has("#webhook-#{every.id} [role='cell']", text: "Every product")
    |> assert_has("#webhook-#{every.id} [role='cell'] span", text: "Device connected", exact: true)
    |> assert_has("#webhook-#{every.id} [role='cell'] span", text: "+2", exact: true)
    |> assert_has("#webhook-#{every.id} p", text: "Every product · 3 events")
    |> assert_has("#webhook-#{some.id} [role='cell'] span", text: "+1", exact: true)
    |> assert_has("#webhook-#{some.id} p", text: "+1 · 1 event")
  end

  test "says what is wrong with an invalid webhook", %{conn: conn, org: org} do
    conn
    |> visit(integrations_path(org))
    |> click_button("Add webhook")
    |> unwrap(fn view ->
      view
      |> form("#webhook-form", webhook: %{url: "ftp://example.com", events: [""]})
      |> render_submit()
    end)
    |> assert_has("#webhook-form", text: "must start with https:// or http://")
    |> assert_has("#webhook-form", text: "choose at least one event")

    assert Webhooks.list_webhooks(org) == []
  end

  test "edits a webhook's events", context do
    %{conn: conn, org: org} = context
    webhook = webhook_fixture(context)

    conn
    |> visit(integrations_path(org))
    |> within("#webhook-#{webhook.id}", &click_button(&1, "Edit"))
    |> assert_has("#webhook-dialog h2", text: "Edit hooks.example.com")
    |> unwrap(fn view ->
      view
      |> form("#webhook-form", webhook: %{events: ["", "device.disconnected"]})
      |> render_submit()
    end)
    |> assert_has("[role='alert']", text: "The webhook was updated.")
    |> assert_has("#webhook-#{webhook.id} [role='cell']", text: "Device disconnected")

    assert %Webhook{events: ["device.disconnected"]} = Repo.reload!(webhook)
  end

  test "turns a webhook off and on", context do
    %{conn: conn, org: org} = context
    webhook = webhook_fixture(context)

    session =
      conn
      |> visit(integrations_path(org))
      |> within("#webhook-#{webhook.id}", &click_button(&1, "Turn off"))
      |> assert_has("#webhook-#{webhook.id} span", text: "Off", exact: true)

    refute Repo.reload!(webhook).enabled

    session
    |> within("#webhook-#{webhook.id}", &click_button(&1, "Turn on"))
    |> refute_has("#webhook-#{webhook.id} span", text: "Off", exact: true)

    assert Repo.reload!(webhook).enabled
  end

  test "shows why a webhook was turned off, and that one is failing", context do
    %{conn: conn, org: org} = context
    failing = webhook_fixture(context)
    :ok = Webhooks.record_failure(failing, 500, "HTTP 500")

    gone = webhook_fixture(context)
    :disabled = Webhooks.record_failure(gone, 410, "HTTP 410")

    conn
    |> visit(integrations_path(org))
    |> assert_has("#webhook-#{failing.id} span", text: "Failing")
    |> assert_has("#webhook-#{failing.id} p", text: "got HTTP 500.")
    |> assert_has("#webhook-#{gone.id} span", text: "Off", exact: true)
    |> assert_has("#webhook-#{gone.id} p", text: "410 Gone")
  end

  test "regenerates a webhook's secret", context do
    %{conn: conn, org: org} = context
    webhook = webhook_fixture(context)

    conn
    |> visit(integrations_path(org))
    |> within("#webhook-#{webhook.id}", &click_button(&1, "New signing secret"))
    |> assert_has("[role='alert']", text: "A new signing secret was generated.")

    refute Repo.reload!(webhook).secret == webhook.secret
  end

  test "removes a webhook", context do
    %{conn: conn, org: org} = context
    webhook = webhook_fixture(context)

    conn
    |> visit(integrations_path(org))
    |> within("#webhook-#{webhook.id}", &click_button(&1, "Delete webhook"))
    |> assert_has("[role='alert']", text: "The webhook to hooks.example.com was removed.")
    |> refute_has("#webhook-#{webhook.id}")
    |> assert_has("#integration-choices")

    assert Webhooks.list_webhooks(org) == []
  end

  test "sends a signed test event and shows the answer", context do
    %{conn: conn, org: org} = context
    webhook = webhook_fixture(context)
    test_pid = self()

    Req.Test.stub(Webhooks, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:delivered, Map.new(conn.req_headers), body})
      Plug.Conn.send_resp(conn, 202, "")
    end)

    conn
    |> visit(integrations_path(org))
    |> within("#webhook-#{webhook.id}", &click_button(&1, "Send test event"))
    |> unwrap(&render_async/1)
    |> assert_has("[role='alert']", text: "The test event was delivered to hooks.example.com, which answered HTTP 202.")

    assert_received {:delivered, headers, body}
    assert %{"type" => "webhook.test", "data" => %{"org" => %{"name" => org_name}} = data} = Jason.decode!(body)
    assert org_name == org.name
    refute Map.has_key?(data, "product")

    assert Signature.verify(
             webhook.secret,
             headers["webhook-id"],
             headers["webhook-timestamp"],
             body,
             headers["webhook-signature"]
           )
  end

  test "reports a test event the endpoint refused", context do
    %{conn: conn, org: org} = context
    webhook = webhook_fixture(context)

    Req.Test.stub(Webhooks, &Plug.Conn.send_resp(&1, 500, ""))

    conn
    |> visit(integrations_path(org))
    |> within("#webhook-#{webhook.id}", &click_button(&1, "Send test event"))
    |> unwrap(&render_async/1)
    |> assert_has("[role='alert']", text: "The test event to hooks.example.com failed: HTTP 500")

    # A test is recorded nowhere: it says nothing about real deliveries.
    assert %Webhook{failing_since: nil} = Repo.reload!(webhook)
  end

  test "turns off the menu's Webhook item at the limit", context do
    %{conn: conn, org: org} = context
    for _ <- 1..Webhooks.max_webhooks_per_org(), do: webhook_fixture(context)

    conn
    |> visit(integrations_path(org))
    |> assert_has("#add-webhook[disabled]", text: "the most it can have")
    |> refute_has("#add-teams-channel[disabled]")
    |> assert_has("#webhooks p", text: "This organization has the most webhooks it can have")
  end

  describe "Slack" do
    setup %{org: org, user: user} do
      %{connection: Fixtures.slack_connection_fixture(org, user)}
    end

    defp stub_slack(answers) do
      test_pid = self()

      Req.Test.stub(Slack, fn conn ->
        method = List.last(conn.path_info)
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:slack, method, body})
        Req.Test.json(conn, Map.fetch!(answers, method))
      end)
    end

    defp channels() do
      %{
        "ok" => true,
        "channels" => [
          %{"id" => "C0FLEET", "name" => "fleet", "is_private" => false},
          %{"id" => "G0OPS", "name" => "ops", "is_private" => true}
        ],
        "response_metadata" => %{"next_cursor" => ""}
      }
    end

    defp subscribe(%{org: org, user: user, connection: connection}, attrs \\ %{}) do
      attrs =
        Map.merge(
          %{"channel_id" => "C0FLEET", "channel_name" => "fleet", "events" => ["device.health_status_changed"]},
          attrs
        )

      {:ok, subscription} =
        Subscriptions.create_subscription(%Scope{org: org, user: user, role: :admin}, connection, attrs)

      subscription
    end

    test "lists the connected workspaces, who connected them, and their channels", context do
      %{conn: conn, connection: connection, org: org, user: user} = context
      subscription = subscribe(context)

      conn
      |> visit(integrations_path(org))
      |> assert_has("#slack-connection-#{connection.id} p", text: "Acme Fleet Slack workspace")
      |> assert_has("#slack-connection-#{connection.id} p", text: "connected by #{user.name} in")
      |> assert_has("#slack-subscription-#{subscription.id} h3", text: "#fleet")
      |> assert_has("#slack-subscription-#{subscription.id} div", text: "Slack · Acme Fleet workspace")
      |> assert_has("#slack-subscription-#{subscription.id} [role='cell']", text: "Health status changed")
      |> assert_has("#slack-subscription-#{subscription.id} [role='cell']", text: "Every product")
      |> assert_has("#add-slack-channel-#{connection.id}", text: "In the Acme Fleet workspace")
      |> assert_has("#connect-slack-workspace", text: "Connect another Slack workspace")
    end

    test "says a workspace installed before link previews needs installing again", context do
      %{conn: conn, connection: connection, org: org} = context

      conn
      |> visit(integrations_path(org))
      |> refute_has("#slack-connection-#{connection.id} p", text: "installs the app again")

      connection.workspace
      |> Ecto.Changeset.change(scopes: Slack.scopes() -- ["links:read", "links:write"])
      |> Repo.update!()

      conn
      |> visit(integrations_path(org))
      |> assert_has("#slack-connection-#{connection.id} p",
        text:
          "To preview NervesHub links posted in this workspace, an admin of this organization installs the app again"
      )
    end

    test "says when a connected workspace has no channels yet", %{conn: conn, connection: connection, org: org} do
      conn
      |> visit(integrations_path(org))
      |> refute_has("#integration-choices")
      |> assert_has("#chat-channels p", text: "No channel gets this organization's events yet.")
      |> assert_has("#slack-connection-#{connection.id}")
    end

    test "offers to add Slack when no workspace is connected", %{conn: conn, connection: connection, org: org} do
      Repo.delete!(connection)

      conn
      |> visit(integrations_path(org))
      |> assert_has("#integration-choices button", text: "Add to Slack")
    end

    test "adds a channel from those Slack lists", context do
      %{conn: conn, connection: connection, org: org, product: product} = context
      stub_slack(%{"conversations.list" => channels()})

      conn
      |> visit(integrations_path(org))
      |> click_button("#add-slack-channel-#{connection.id}", "Slack channel")
      |> unwrap(&render_async/1)
      |> assert_has("#slack-dialog h2", text: "Add a Slack channel")
      |> assert_has("#slack-subscription-channel option", text: "#fleet")
      |> assert_has("#slack-subscription-channel option", text: "ops (private)")
      |> unwrap(fn view ->
        view
        |> form("#slack-subscription-form", slack_subscription: %{channel_id: "G0OPS", all_products: "false"})
        |> render_change()

        view
        |> form("#slack-subscription-form",
          slack_subscription: %{
            channel_id: "G0OPS",
            all_products: "false",
            products: ["", product.name],
            events: ["", "device.firmware_update.failed"]
          }
        )
        |> render_submit()
      end)
      |> assert_has("[role='alert']", text: "NervesHub will post to #ops.")
      |> assert_has("#chat-channels h3", text: "#ops")

      assert [%{subscriptions: [subscription]}] = Slack.list_connections(org)

      assert %{channel_id: "G0OPS", channel_name: "ops", all_products: false, events: ["device.firmware_update.failed"]} =
               subscription

      assert [%{name: name}] = subscription.products
      assert name == product.name
    end

    test "refuses a channel Slack did not list", context do
      %{conn: conn, connection: connection, org: org} = context
      stub_slack(%{"conversations.list" => channels()})

      conn
      |> visit(integrations_path(org))
      |> click_button("#add-slack-channel-#{connection.id}", "Slack channel")
      |> unwrap(&render_async/1)
      |> unwrap(fn view ->
        view
        |> element("#slack-subscription-form")
        |> render_submit(%{
          "slack_subscription" => %{
            "channel_id" => "C0SOMEONE",
            "all_products" => "true",
            "events" => ["", "device.health_status_changed"]
          }
        })
      end)
      |> assert_has("[role='alert']", text: "Choose a channel from the list.")

      assert [%{subscriptions: []}] = Slack.list_connections(org)
    end

    test "says so when Slack will not list the channels", context do
      %{conn: conn, connection: connection, org: org} = context
      stub_slack(%{"conversations.list" => %{"ok" => false, "error" => "missing_scope"}})

      conn
      |> visit(integrations_path(org))
      |> click_button("#add-slack-channel-#{connection.id}", "Slack channel")
      |> unwrap(&render_async/1)
      |> assert_has("#slack-subscription-form", text: "Slack did not list the workspace's channels: missing_scope")
    end

    test "edits, turns off and removes a channel", context do
      %{conn: conn, org: org} = context
      subscription = subscribe(context)

      session =
        conn
        |> visit(integrations_path(org))
        |> within("#slack-subscription-#{subscription.id}", &click_button(&1, "Edit"))
        |> assert_has("#slack-dialog h2", text: "Edit #fleet")
        |> unwrap(fn view ->
          view
          |> form("#slack-subscription-form",
            slack_subscription: %{all_products: "true", events: ["", "product.notification_created"]}
          )
          |> render_submit()
        end)
        |> assert_has("[role='alert']", text: "The channel was updated.")
        |> assert_has("#slack-subscription-#{subscription.id} [role='cell']", text: "Product notifications")
        |> within("#slack-subscription-#{subscription.id}", &click_button(&1, "Turn off"))
        |> assert_has("#slack-subscription-#{subscription.id} span", text: "Off", exact: true)

      refute Repo.reload!(subscription).enabled

      session
      |> within("#slack-subscription-#{subscription.id}", &click_button(&1, "Delete channel"))
      |> assert_has("[role='alert']", text: "NervesHub stopped posting to #fleet.")
      |> refute_has("#slack-subscription-#{subscription.id}")
    end

    test "sends a test message", context do
      %{conn: conn, org: org} = context
      subscription = subscribe(context)
      stub_slack(%{"chat.postMessage" => %{"ok" => true}})

      conn
      |> visit(integrations_path(org))
      |> within("#slack-subscription-#{subscription.id}", &click_button(&1, "Send test message"))
      |> unwrap(&render_async/1)
      |> assert_has("[role='alert']", text: "Posted a test message to #fleet.")

      assert_received {:slack, "chat.postMessage", _body}
    end

    test "shows why a channel was turned off", context do
      %{conn: conn, org: org} = context
      subscription = subscribe(context)

      subscription
      |> Ecto.Changeset.change(enabled: false, disabled_reason: "Turned off because the channel was archived.")
      |> Repo.update!()

      conn
      |> visit(integrations_path(org))
      |> assert_has("#slack-subscription-#{subscription.id} span", text: "Off", exact: true)
      |> assert_has("#slack-subscription-#{subscription.id} p", text: "the channel was archived")
    end

    test "disconnects a workspace", context do
      %{conn: conn, connection: connection, org: org} = context
      stub_slack(%{"auth.revoke" => %{"ok" => true, "revoked" => true}})

      conn
      |> visit(integrations_path(org))
      |> within("#slack-connection-#{connection.id}", &click_button(&1, "Disconnect"))
      |> assert_has("[role='alert']", text: "Disconnected the Acme Fleet Slack workspace.")
      |> refute_has("#slack-connection-#{connection.id}")
      |> assert_has("#integration-choices")

      assert Slack.list_connections(org) == []
    end

    test "a manager chooses channels, but only an admin connects workspaces", context do
      %{conn: conn, connection: connection, org: org} = context
      Repo.update_all(OrgUser, set: [role: :manage])

      session =
        conn
        |> visit(integrations_path(org))
        |> refute_has("#add-integration-menu-toggle[disabled]")
        |> refute_has("#add-slack-channel-#{connection.id}[disabled]")
        |> assert_has("#connect-slack-workspace[disabled]", text: "Admins only")
        |> refute_has("#slack-connection-#{connection.id} button", text: "Disconnect")

      session.view
      |> with_target("#slack")
      |> render_click("disconnect", %{"connection_id" => connection.id})

      assert render(session.view) =~ "Sorry. You were denied access. Please check your role or contact your support."
      assert Repo.reload(connection)
    end

    test "a viewer sees the channels, but cannot change them", context do
      %{conn: conn, org: org} = context
      subscription = subscribe(context)
      Repo.update_all(OrgUser, set: [role: :view])

      session =
        conn
        |> visit(integrations_path(org))
        |> assert_has("#slack-subscription-#{subscription.id} h3", text: "#fleet")
        |> assert_has("#add-integration-menu-toggle[disabled]")
        |> refute_has("#slack-subscription-#{subscription.id}-menu-toggle")

      session.view
      |> with_target("#slack")
      |> render_click("delete", %{"subscription_id" => subscription.id})

      assert render(session.view) =~ "Sorry. You were denied access. Please check your role or contact your support."
      assert Repo.reload(subscription)
    end

    test "is hidden when the instance has no Slack app", %{conn: conn, org: org} do
      config = Application.get_env(:nerves_hub, Slack)
      on_exit(fn -> Application.put_env(:nerves_hub, Slack, config) end)
      Application.put_env(:nerves_hub, Slack, Keyword.put(config, :client_id, nil))

      conn
      |> visit(integrations_path(org))
      |> refute_has("#slack")
      |> refute_has("#integration-choices h3", text: "Slack")
      |> assert_has("#integration-choices h3", text: "Webhook")
    end
  end

  describe "Microsoft Teams" do
    @teams_url "https://prod-07.westeurope.logic.azure.com:443/workflows/1f2e/triggers/manual/paths/invoke?api-version=2016-06-01&sv=1.0&sig=c2VrcmV0LXNpZw"

    defp teams_channel(%{org: org, user: user}, attrs \\ %{}) do
      attrs =
        Map.merge(
          %{"name" => "Fleet alerts", "url" => @teams_url, "events" => ["device.health_status_changed"]},
          attrs
        )

      {:ok, channel} = ChatWebhooks.create_channel(%Scope{org: org, user: user, role: :admin}, :teams, attrs)
      channel
    end

    test "lists the channels and what they get, but never a URL", context do
      %{conn: conn, org: org} = context
      channel = teams_channel(context)

      conn
      |> visit(integrations_path(org))
      |> assert_has("#teams-channel-#{channel.id} h3", text: "Fleet alerts")
      |> assert_has("#teams-channel-#{channel.id} div", text: "Microsoft Teams · Workflows webhook")
      |> assert_has("#teams-channel-#{channel.id} [role='cell']", text: "Health status changed")
      |> assert_has("#teams-channel-#{channel.id} [role='cell']", text: "Every product")
      |> unwrap(fn view ->
        html = render(view)
        refute html =~ "c2VrcmV0LXNpZw"
        html
      end)
    end

    test "shows that posting to a channel failed", context do
      %{conn: conn, org: org} = context
      channel = teams_channel(context)

      channel
      |> Ecto.Changeset.change(
        last_error: "Teams answered 403 Forbidden.",
        last_error_at: DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

      conn
      |> visit(integrations_path(org))
      |> assert_has("#teams-channel-#{channel.id} span", text: "Failing")
      |> assert_has("#teams-channel-#{channel.id} p", text: "Teams answered 403 Forbidden.")
    end

    test "adds a channel from a Workflows webhook's URL", %{conn: conn, org: org} do
      conn
      |> visit(integrations_path(org))
      |> click_button("Add Teams channel")
      |> assert_has("#teams-dialog h2", text: "Add a Microsoft Teams channel")
      |> assert_has("#teams-dialog ol li", text: "Send webhook alerts to a channel")
      |> unwrap(fn view ->
        view
        |> form("#teams-channel-form",
          teams_channel: %{name: "Fleet alerts", url: @teams_url, events: ["", "device.firmware_update.failed"]}
        )
        |> render_submit()
      end)
      |> refute_has("#teams-channel-form")
      |> assert_has("#teams h3", text: "Fleet alerts")

      assert [%{name: "Fleet alerts", url: @teams_url, events: ["device.firmware_update.failed"]}] =
               ChatWebhooks.list_channels(org, :teams)
    end

    test "adds another channel from the Add integration menu", context do
      %{conn: conn, org: org} = context
      teams_channel(context)

      conn
      |> visit(integrations_path(org))
      |> click_button("#add-teams-channel", "Microsoft Teams channel")
      |> assert_has("#teams-dialog h2", text: "Add a Microsoft Teams channel")
    end

    test "says what is wrong with a URL that is not a Workflows webhook's", %{conn: conn, org: org} do
      conn
      |> visit(integrations_path(org))
      |> click_button("Add Teams channel")
      |> unwrap(fn view ->
        view
        |> form("#teams-channel-form",
          teams_channel: %{
            name: "Old",
            url: "https://acme.webhook.office.com/webhookb2/abc",
            events: ["", "device.firmware_update.failed"]
          }
        )
        |> render_submit()
      end)
      |> assert_has("#teams-channel-form p", text: "is an Office 365 connector URL")

      assert ChatWebhooks.list_channels(org, :teams) == []
    end

    test "editing leaves the URL out of the page, and keeps it unless a new one is given", context do
      %{conn: conn, org: org} = context
      channel = teams_channel(context)

      conn
      |> visit(integrations_path(org))
      |> within("#teams-channel-#{channel.id}", &click_button(&1, "Edit"))
      |> assert_has("#teams-dialog h2", text: "Edit Fleet alerts")
      |> assert_has("#teams-channel-form label", text: "New Workflows webhook URL")
      |> refute_has("#teams-dialog ol")
      |> unwrap(fn view ->
        refute render(view) =~ "c2VrcmV0LXNpZw"

        view
        |> form("#teams-channel-form", teams_channel: %{name: "Renamed", url: ""})
        |> render_submit()
      end)
      |> assert_has("[role='alert']", text: "The channel was updated.")

      assert %{name: "Renamed", url: @teams_url} = Repo.reload!(channel)
    end

    test "a viewer sees the channels, but cannot change them", context do
      %{conn: conn, org: org} = context
      channel = teams_channel(context)
      Repo.update_all(OrgUser, set: [role: :view])

      session =
        conn
        |> visit(integrations_path(org))
        |> assert_has("#teams-channel-#{channel.id} h3", text: "Fleet alerts")
        |> assert_has("#add-integration-menu-toggle[disabled]")
        |> refute_has("#teams-channel-#{channel.id}-menu-toggle")

      session.view
      |> with_target("#teams")
      |> render_click("delete", %{"channel_id" => channel.id})

      assert render(session.view) =~ "Sorry. You were denied access. Please check your role or contact your support."
      assert Repo.reload(channel)
    end
  end

  describe "Discord" do
    test "adds a channel from a Discord webhook's URL", %{conn: conn, org: org} do
      url = "https://discord.com/api/webhooks/123456789012345678/AbC-dEf_GhI"

      conn
      |> visit(integrations_path(org))
      |> click_button("Add Discord channel")
      |> assert_has("#discord-dialog h2", text: "Add a Discord channel")
      |> unwrap(fn view ->
        view
        |> form("#discord-channel-form",
          discord_channel: %{name: "#fleet", url: url, events: ["", "device.firmware_update.failed"]}
        )
        |> render_submit()
      end)
      |> refute_has("#discord-channel-form")
      |> assert_has("#discord h3", text: "#fleet")
      |> assert_has("#discord div", text: "Discord · Channel webhook")

      assert [%{name: "#fleet", provider: :discord, url: ^url}] = ChatWebhooks.list_channels(org, :discord)
      assert ChatWebhooks.list_channels(org, :teams) == []
    end
  end

  describe "a member who cannot manage integrations" do
    test "sees the choices, but cannot pick one", %{conn: conn, org: org} do
      Repo.update_all(OrgUser, set: [role: :view])

      conn
      |> visit(integrations_path(org))
      |> assert_has("#integration-choices button[disabled]", text: "Add to Slack")
      |> assert_has("#integration-choices button[disabled]", text: "Add Teams channel")
      |> assert_has("#integration-choices button[disabled]", text: "Add webhook")
    end

    test "sees each webhook's host and events, but not its URL or secret", context do
      %{conn: conn, org: org} = context
      webhook = webhook_fixture(context)
      Repo.update_all(OrgUser, set: [role: :view])

      conn
      |> visit(integrations_path(org))
      |> assert_has("#webhook-#{webhook.id} code", text: "hooks.example.com")
      |> assert_has("#webhook-#{webhook.id} [role='cell']", text: "Device connected")
      |> refute_has("#webhook-#{webhook.id} code", text: "sekrit")
      |> refute_has("#webhook-#{webhook.id}-copy-secret")
      |> refute_has("#webhook-#{webhook.id}-menu-toggle")
      |> assert_has("#add-integration-menu-toggle[disabled]")
    end

    test "cannot change a webhook by sending the event anyway", context do
      %{conn: conn, org: org} = context
      webhook = webhook_fixture(context)
      Repo.update_all(OrgUser, set: [role: :view])

      session = visit(conn, integrations_path(org))

      assert render_click(session.view, "delete", %{"webhook_id" => webhook.id}) =~
               "Sorry. You were denied access. Please check your role or contact your support."

      assert Repo.reload!(webhook)
    end
  end
end
