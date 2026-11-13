defmodule NervesHub.Workers.DeliverWebhookTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHub.Products.Notification
  alias NervesHub.Webhooks
  alias NervesHub.Webhooks.Signature
  alias NervesHub.Webhooks.Webhook
  alias NervesHub.Workers.DeliverWebhook

  @body ~s({"type":"device.connected","timestamp":"2026-10-13T09:00:00Z","data":{}})

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    scope = %Scope{org: org, product: product, user: user}

    {:ok, webhook} =
      Webhooks.create_webhook(scope, %{"url" => "https://example.com/hooks", "events" => ["device.connected"]})

    %{scope: scope, webhook: webhook}
  end

  defp args(webhook), do: %{"webhook_id" => webhook.id, "event_id" => "msg_test", "body" => @body}

  defp respond_with(status, headers \\ []) do
    test_pid = self()

    Req.Test.stub(Webhooks, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:delivered, conn, body})

      headers
      |> Enum.reduce(conn, fn {name, value}, conn -> Plug.Conn.put_resp_header(conn, name, value) end)
      |> Plug.Conn.send_resp(status, "")
    end)
  end

  test "posts the event, signed so the receiver can verify it", %{webhook: webhook} do
    respond_with(200)

    assert :ok = perform_job(DeliverWebhook, args(webhook))

    assert_received {:delivered, conn, @body}
    assert conn.method == "POST"
    assert conn.request_path == "/hooks"

    headers = Map.new(conn.req_headers)
    assert headers["content-type"] == "application/json"
    assert headers["webhook-id"] == "msg_test"

    timestamp = String.to_integer(headers["webhook-timestamp"])
    assert_in_delta timestamp, System.os_time(:second), 5
    assert Signature.verify(webhook.secret, "msg_test", timestamp, @body, headers["webhook-signature"])
  end

  test "a success clears a failing webhook", %{webhook: webhook} do
    :ok = Webhooks.record_failure(webhook, 500, "HTTP 500")
    respond_with(204)

    # Past the cool-down, so this delivery is actually attempted.
    Webhook
    |> where(id: ^webhook.id)
    |> Repo.update_all(set: [last_error_at: DateTime.add(DateTime.utc_now(:second), -60)])

    assert :ok = perform_job(DeliverWebhook, args(webhook))
    assert %Webhook{failing_since: nil} = Repo.reload!(webhook)
  end

  test "a refused delivery is retried later, without counting as a job error", %{webhook: webhook} do
    respond_with(500)

    assert {:snooze, delay} = perform_job(DeliverWebhook, args(webhook))
    assert delay in 5..6

    assert %Webhook{failing_since: %DateTime{}, last_error: "HTTP 500"} = Repo.reload!(webhook)
  end

  test "backs off further with each retry", %{webhook: webhook} do
    respond_with(500)

    assert {:snooze, delay} = perform_job(DeliverWebhook, args(webhook), meta: %{"snoozed" => 3})
    assert delay in 1800..1980
  end

  test "gives up after the last retry", %{webhook: webhook} do
    respond_with(503)

    assert {:cancel, reason} = perform_job(DeliverWebhook, args(webhook), meta: %{"snoozed" => 5})
    assert reason == "gave up after 6 attempts: HTTP 503"
  end

  test "does not follow redirects", %{webhook: webhook} do
    respond_with(301, [{"location", "http://169.254.169.254/latest"}])

    assert {:snooze, _delay} = perform_job(DeliverWebhook, args(webhook))

    assert %Webhook{last_error: "HTTP 301: redirected to http://169.254.169.254/latest, which is not followed"} =
             Repo.reload!(webhook)
  end

  test "reports a connection failure", %{webhook: webhook} do
    Req.Test.stub(Webhooks, &Req.Test.transport_error(&1, :econnrefused))

    assert {:snooze, _delay} = perform_job(DeliverWebhook, args(webhook))
    assert %Webhook{last_error: "connection refused"} = Repo.reload!(webhook)
  end

  test "turns the webhook off when the endpoint answers 410 Gone", %{webhook: webhook} do
    respond_with(410)

    assert {:cancel, "the webhook was turned off: HTTP 410"} = perform_job(DeliverWebhook, args(webhook))
    assert %Webhook{enabled: false} = Repo.reload!(webhook)
    assert [%Notification{level: :error}] = Repo.all(Notification)
  end

  test "skips the request while the endpoint is cooling down", %{webhook: webhook} do
    :ok = Webhooks.record_failure(webhook, nil, "timeout")
    Req.Test.stub(Webhooks, fn _conn -> flunk("sent a request to an endpoint that failed moments ago") end)

    assert {:snooze, _delay} = perform_job(DeliverWebhook, args(webhook))
  end

  test "drops the delivery when the webhook was deleted or turned off", %{scope: scope, webhook: webhook} do
    Req.Test.stub(Webhooks, fn _conn -> flunk("delivered to a webhook that is off") end)

    {:ok, _} = Webhooks.update_webhook(scope, webhook, %{"enabled" => false})
    assert {:cancel, _} = perform_job(DeliverWebhook, args(webhook))

    {:ok, _} = Webhooks.delete_webhook(scope, Repo.reload!(webhook))
    assert {:cancel, _} = perform_job(DeliverWebhook, args(webhook))
  end
end
