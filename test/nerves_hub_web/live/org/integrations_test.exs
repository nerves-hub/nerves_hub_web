defmodule NervesHubWeb.Live.Org.IntegrationsTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Slack
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

  test "is in the organization's sidebar", %{conn: conn, org: org} do
    conn
    |> visit("/org/#{org.name}/settings/keys")
    |> click_link("Integrations")
    |> assert_path(integrations_path(org))
    |> assert_has("div", text: "Webhooks")
    |> assert_has("p", text: "This organization has no webhooks.")
  end

  test "is no longer a tab of the product settings", %{conn: conn, org: org, product: product} do
    conn
    |> visit("/org/#{org.name}/#{product.name}/settings")
    |> refute_has("a", text: "Integrations")
  end

  test "keeps the explanation short, with the rest a click away", %{conn: conn, org: org} do
    conn
    |> visit(integrations_path(org))
    |> assert_has("p", text: "as a signed JSON POST.")
    |> assert_has("#webhooks-show-more", text: "Show more")
    |> assert_has("#webhooks-more[style*='display: none']", text: "410 Gone")
    |> assert_has("#webhooks-more button", text: "Show less")
  end

  test "adds a webhook", %{conn: conn, org: org} do
    conn
    |> visit(integrations_path(org))
    |> click_button("Add webhook")
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
    |> assert_has("span", text: "Fleet dashboard")
    |> assert_has("code", text: "https://hooks.example.com/nerves")
    |> assert_has("code", text: "device.firmware_update.finished")

    assert [
             %Webhook{
               events: ["device.connected", "device.firmware_update.finished"],
               all_products: true,
               enabled: true
             }
           ] = Webhooks.list_webhooks(org)
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
    |> assert_has("div", text: "Products: #{product.name}")

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

  test "shows the products each webhook sends events for", context do
    %{conn: conn, org: org, product: product} = context
    every = webhook_fixture(context)
    some = webhook_fixture(context, %{"products" => [product.name]})

    conn
    |> visit(integrations_path(org))
    |> assert_has("#webhook-#{every.id} div", text: "Products: Every product")
    |> assert_has("#webhook-#{some.id} div", text: "Products: #{product.name}")
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
    |> unwrap(fn view ->
      view
      |> form("#webhook-form", webhook: %{events: ["", "device.disconnected"]})
      |> render_submit()
    end)
    |> assert_has("[role='alert']", text: "The webhook was updated.")

    assert %Webhook{events: ["device.disconnected"]} = Repo.reload!(webhook)
  end

  test "turns a webhook off and on", context do
    %{conn: conn, org: org} = context
    webhook = webhook_fixture(context)

    session =
      conn
      |> visit(integrations_path(org))
      |> within("#webhook-#{webhook.id}", &click_button(&1, "Turn off"))
      |> assert_has("#webhook-#{webhook.id} span", text: "Off")

    refute Repo.reload!(webhook).enabled

    session
    |> within("#webhook-#{webhook.id}", &click_button(&1, "Turn on"))
    |> assert_has("#webhook-#{webhook.id} span", text: "On")

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
    |> assert_has("#webhook-#{failing.id} p", text: "HTTP 500")
    |> assert_has("#webhook-#{gone.id} span", text: "Off")
    |> assert_has("#webhook-#{gone.id} p", text: "410 Gone")
  end

  test "regenerates a webhook's secret", context do
    %{conn: conn, org: org} = context
    webhook = webhook_fixture(context)

    conn
    |> visit(integrations_path(org))
    |> within("#webhook-#{webhook.id}", &click_button(&1, "Regenerate"))
    |> assert_has("[role='alert']", text: "A new signing secret was generated.")

    refute Repo.reload!(webhook).secret == webhook.secret
  end

  test "removes a webhook", context do
    %{conn: conn, org: org} = context
    webhook = webhook_fixture(context)

    conn
    |> visit(integrations_path(org))
    |> within("#webhook-#{webhook.id}", &click_button(&1, "Delete"))
    |> assert_has("[role='alert']", text: "The webhook to hooks.example.com was removed.")
    |> refute_has("#webhook-#{webhook.id}")

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

  test "hides the add button at the limit", context do
    %{conn: conn, org: org} = context
    for _ <- 1..Webhooks.max_webhooks_per_org(), do: webhook_fixture(context)

    conn
    |> visit(integrations_path(org))
    |> refute_has("button", text: "Add webhook")
    |> assert_has("p", text: "This organization has the most webhooks it can have")
  end

  describe "Slack" do
    defp connect_slack(%{org: org, user: user}, team \\ %{"name" => "Acme Fleet", "id" => "T9TK3CUKW"}) do
      Req.Test.stub(Slack, fn conn ->
        case conn.path_info do
          [_, "oauth.v2.access"] ->
            Req.Test.json(conn, %{
              "ok" => true,
              "access_token" => "xoxb-a-bot-token",
              "token_type" => "bot",
              "bot_user_id" => "U0KRQLJ9H",
              "app_id" => "A0KRD7HC3",
              "team" => team
            })

          [_, "auth.revoke"] ->
            Req.Test.json(conn, %{"ok" => true, "revoked" => true})
        end
      end)

      {:ok, connection} =
        Slack.connect(%Scope{org: org, user: user, role: :admin}, "a-code", "https://example.com/callback")

      connection
    end

    test "lists the connected workspaces, and who connected them", context do
      %{conn: conn, org: org, user: user} = context
      connection = connect_slack(context)

      conn
      |> visit(integrations_path(org))
      |> assert_has("#slack button", text: "Add to Slack")
      |> assert_has("#slack-connection-#{connection.id} span", text: "Acme Fleet")
      |> assert_has("#slack-connection-#{connection.id} span", text: "Connected by #{user.name}")
    end

    test "says when no workspace is connected", %{conn: conn, org: org} do
      conn
      |> visit(integrations_path(org))
      |> assert_has("#slack p", text: "No Slack workspace is connected.")
    end

    test "disconnects a workspace", context do
      %{conn: conn, org: org} = context
      connection = connect_slack(context)

      conn
      |> visit(integrations_path(org))
      |> within("#slack-connection-#{connection.id}", &click_button(&1, "Disconnect"))
      |> assert_has("[role='alert']", text: "Disconnected the Acme Fleet Slack workspace.")
      |> refute_has("#slack-connection-#{connection.id}")

      assert Slack.list_connections(org) == []
    end

    test "is for admins to change", context do
      %{conn: conn, org: org} = context
      connection = connect_slack(context)
      Repo.update_all(OrgUser, set: [role: :manage])

      session =
        conn
        |> visit(integrations_path(org))
        |> assert_has("#slack-connection-#{connection.id} span", text: "Acme Fleet")
        |> refute_has("#slack button", text: "Add to Slack")
        |> refute_has("#slack-connection-#{connection.id} button", text: "Disconnect")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(session.view, "disconnect-slack", %{"connection_id" => connection.id}))
    end

    test "is hidden when the instance has no Slack app", %{conn: conn, org: org} do
      config = Application.get_env(:nerves_hub, Slack)
      on_exit(fn -> Application.put_env(:nerves_hub, Slack, config) end)
      Application.put_env(:nerves_hub, Slack, Keyword.put(config, :client_id, nil))

      conn
      |> visit(integrations_path(org))
      |> refute_has("#slack")
      |> assert_has("div", text: "Webhooks")
    end
  end

  describe "a member who cannot manage webhooks" do
    setup context do
      webhook = webhook_fixture(context)
      Repo.update_all(OrgUser, set: [role: :view])

      %{webhook: webhook}
    end

    test "sees each webhook's host and events, but not its URL or secret", %{
      conn: conn,
      org: org,
      webhook: webhook
    } do
      conn
      |> visit(integrations_path(org))
      |> assert_has("#webhook-#{webhook.id} code", text: "hooks.example.com")
      |> assert_has("#webhook-#{webhook.id} code", text: "device.connected")
      |> refute_has("#webhook-#{webhook.id} code", text: "sekrit")
      |> refute_has("#webhook-#{webhook.id}-copy-secret")
      |> refute_has("#webhook-#{webhook.id} button", text: "Send test event")
      |> refute_has("#webhook-#{webhook.id}-menu-toggle")
    end

    test "cannot change a webhook by sending the event anyway", %{
      conn: conn,
      org: org,
      webhook: webhook
    } do
      session = visit(conn, integrations_path(org))

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(session.view, "delete", %{"webhook_id" => webhook.id}))

      assert Repo.reload!(webhook)
    end
  end
end
