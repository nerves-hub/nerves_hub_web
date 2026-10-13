defmodule NervesHubWeb.API.WebhookControllerTest do
  use NervesHubWeb.APIConnCase, async: false

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHub.Webhooks
  alias NervesHub.Webhooks.Signature
  alias NervesHub.Webhooks.Webhook

  defp webhooks_path(org, product), do: ~p"/api/orgs/#{org.name}/products/#{product.name}/webhooks"
  defp webhooks_path(org, product, id), do: ~p"/api/orgs/#{org.name}/products/#{product.name}/webhooks/#{id}"

  defp webhook_fixture(%{org: org, product: product, user: user}, attrs \\ %{}) do
    attrs = Map.merge(%{"url" => "https://hooks.example.com/nerves", "events" => ["device.connected"]}, attrs)
    {:ok, webhook} = Webhooks.create_webhook(%Scope{org: org, product: product, user: user}, attrs)
    webhook
  end

  describe "create" do
    test "adds a webhook and returns its secret, once", %{conn: conn, org: org, product: product, user: user} do
      body = %{
        "url" => "https://hooks.example.com/nerves",
        "description" => "Fleet dashboard",
        "events" => ["device.connected", "device.health_status_changed"]
      }

      data = conn |> post(webhooks_path(org, product), body) |> json_response(201) |> Map.fetch!("data")

      assert %{
               "url" => "https://hooks.example.com/nerves",
               "description" => "Fleet dashboard",
               "events" => ["device.connected", "device.health_status_changed"],
               "enabled" => true,
               "failing_since" => nil,
               "secret" => "whsec_" <> _
             } = data

      assert {:ok, webhook} = Webhooks.fetch_webhook(product, data["id"])
      assert webhook.secret == data["secret"]

      assert [%{actor_id: actor_id}] = AuditLogs.logs_for(product)
      assert actor_id == user.id
    end

    test "says what is wrong with an invalid webhook", %{conn: conn, org: org, product: product} do
      errors =
        conn
        |> post(webhooks_path(org, product), %{"url" => "ftp://example.com", "events" => ["device.exploded"]})
        |> json_response(422)
        |> Map.fetch!("errors")

      assert errors == %{
               "url" => ["must start with https:// or http://"],
               "events" => ["contains an event that does not exist"]
             }
    end

    test "refuses a webhook past the per-product limit", context do
      %{conn: conn, org: org, product: product} = context
      for _ <- 1..Webhooks.max_webhooks_per_product(), do: webhook_fixture(context)

      body = %{"url" => "https://hooks.example.com/one-more", "events" => ["device.connected"]}
      response = conn |> post(webhooks_path(org, product), body) |> json_response(422)

      assert response["errors"]["detail"] =~ "at most 10 webhooks"
    end
  end

  describe "index and show" do
    test "list the product's webhooks without their secrets", context do
      %{conn: conn, org: org, product: product} = context
      first = webhook_fixture(context)
      second = webhook_fixture(context, %{"events" => ["device.disconnected"]})

      data = conn |> get(webhooks_path(org, product)) |> json_response(200) |> Map.fetch!("data")

      assert Enum.map(data, & &1["id"]) == [first.id, second.id]
      refute Enum.any?(data, &Map.has_key?(&1, "secret"))
    end

    test "show one webhook, with its delivery state", context do
      %{conn: conn, org: org, product: product} = context
      webhook = webhook_fixture(context)
      :ok = Webhooks.record_failure(webhook, 500, "HTTP 500")

      data = conn |> get(webhooks_path(org, product, webhook.id)) |> json_response(200) |> Map.fetch!("data")

      assert %{"id" => id, "last_error" => "HTTP 500", "failing_since" => failing_since} = data
      assert id == webhook.id
      assert failing_since
      refute Map.has_key?(data, "secret")
    end

    test "is not found for an unknown id, a malformed one, or another product's webhook", context do
      %{conn: conn, org: org, product: product, user: user} = context
      other_product = Fixtures.product_fixture(user, org, %{name: "other"})
      other = webhook_fixture(%{context | product: other_product})

      assert conn |> get(webhooks_path(org, product, 123_456_789)) |> json_response(404)
      assert conn |> get(webhooks_path(org, product, "not-a-number")) |> json_response(404)
      assert conn |> get(webhooks_path(org, product, other.id)) |> json_response(404)
    end
  end

  describe "update" do
    test "changes the events and turns the webhook off", context do
      %{conn: conn, org: org, product: product} = context
      webhook = webhook_fixture(context)

      data =
        conn
        |> patch(webhooks_path(org, product, webhook.id), %{"events" => ["device.disconnected"], "enabled" => false})
        |> json_response(200)
        |> Map.fetch!("data")

      assert %{"events" => ["device.disconnected"], "enabled" => false} = data
      refute Map.has_key?(data, "secret")
      assert %Webhook{enabled: false, secret: secret} = Repo.reload!(webhook)
      assert secret == webhook.secret
    end

    test "says what is wrong with an invalid change", context do
      %{conn: conn, org: org, product: product} = context
      webhook = webhook_fixture(context)

      errors =
        conn
        |> put(webhooks_path(org, product, webhook.id), %{"events" => []})
        |> json_response(422)
        |> Map.fetch!("errors")

      assert errors == %{"events" => ["choose at least one event"]}
    end
  end

  test "delete removes the webhook", context do
    %{conn: conn, org: org, product: product} = context
    webhook = webhook_fixture(context)

    assert conn |> delete(webhooks_path(org, product, webhook.id)) |> response(204)
    assert {:error, :not_found} = Webhooks.fetch_webhook(product, webhook.id)
  end

  test "regenerate_secret returns a new secret", context do
    %{conn: conn, org: org, product: product} = context
    webhook = webhook_fixture(context)

    data =
      conn
      |> post(webhooks_path(org, product, webhook.id) <> "/regenerate_secret")
      |> json_response(200)
      |> Map.fetch!("data")

    assert "whsec_" <> _ = data["secret"]
    refute data["secret"] == webhook.secret
    assert Repo.reload!(webhook).secret == data["secret"]
  end

  describe "send_test" do
    test "sends a signed test event and reports the answer", context do
      %{conn: conn, org: org, product: product} = context
      webhook = webhook_fixture(context)
      test_pid = self()

      Req.Test.stub(Webhooks, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:delivered, Map.new(conn.req_headers), body})
        Plug.Conn.send_resp(conn, 202, "")
      end)

      data =
        conn
        |> post(webhooks_path(org, product, webhook.id) <> "/test")
        |> json_response(200)
        |> Map.fetch!("data")

      assert data == %{"delivered" => true, "status" => 202, "error" => nil}

      assert_received {:delivered, headers, body}
      assert %{"type" => "webhook.test"} = Jason.decode!(body)

      assert Signature.verify(
               webhook.secret,
               headers["webhook-id"],
               headers["webhook-timestamp"],
               body,
               headers["webhook-signature"]
             )
    end

    test "reports an endpoint that refused it", context do
      %{conn: conn, org: org, product: product} = context
      webhook = webhook_fixture(context)

      Req.Test.stub(Webhooks, &Plug.Conn.send_resp(&1, 500, ""))

      data =
        conn
        |> post(webhooks_path(org, product, webhook.id) <> "/test")
        |> json_response(200)
        |> Map.fetch!("data")

      assert data == %{"delivered" => false, "status" => 500, "error" => "HTTP 500"}
    end
  end

  describe "a view-only member" do
    setup %{org: org, user2: user2} = context do
      {:ok, _} = Accounts.add_org_user(org, user2, %{role: :view})
      %{webhook: webhook_fixture(context)}
    end

    test "cannot list, read, add or change webhooks", context do
      %{conn2: conn2, org: org, product: product, webhook: webhook} = context

      assert_error_sent(401, fn -> get(conn2, webhooks_path(org, product)) end)
      assert_error_sent(401, fn -> get(conn2, webhooks_path(org, product, webhook.id)) end)

      assert_error_sent(401, fn ->
        post(conn2, webhooks_path(org, product), %{
          "url" => "https://evil.example.com",
          "events" => ["device.connected"]
        })
      end)

      assert_error_sent(401, fn -> delete(conn2, webhooks_path(org, product, webhook.id)) end)
      assert_error_sent(401, fn -> post(conn2, webhooks_path(org, product, webhook.id) <> "/regenerate_secret") end)

      assert Repo.reload!(webhook)
      assert [_only_the_fixture] = Webhooks.list_webhooks(product)
    end
  end

  test "the endpoints are in the OpenAPI spec", %{conn: conn} do
    paths = conn |> get("/api/openapi") |> json_response(200) |> Map.fetch!("paths")

    base = "/api/orgs/{org_name}/products/{product_name}/webhooks"

    assert Map.keys(paths["#{base}"]) |> Enum.sort() == ["get", "post"]
    assert Map.keys(paths["#{base}/{id}"]) |> Enum.sort() == ["delete", "get", "patch", "put"]
    assert Map.has_key?(paths["#{base}/{id}/regenerate_secret"], "post")
    assert Map.has_key?(paths["#{base}/{id}/test"], "post")
  end
end
