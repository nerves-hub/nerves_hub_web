defmodule NervesHubWeb.API.AuthRequestControllerTest do
  use NervesHubWeb.APIConnCase, async: false

  import NervesHub.Support.PhoenixTestAssertions
  import PhoenixTest, except: [assert_has: 3, assert_has: 4, refute_has: 3, refute_has: 4]

  alias NervesHub.Accounts
  alias NervesHub.PlugAttack.Storage, as: PlugAttackStorage
  alias NervesHubWeb.AuthRequests
  alias PlugAttack.Storage.Ets, as: PlugAttackEts

  setup do
    PlugAttackEts.clean(PlugAttackStorage)
    on_exit(fn -> PlugAttackEts.clean(PlugAttackStorage) end)
  end

  describe "making a request" do
    test "rejects a request that isn't to the API" do
      for {params, detail} <- [
            {%{"method" => "POST"}, "path is required, starting with /api/"},
            {%{"method" => "TRACE", "path" => "/api/users/me"}, "method must be one of GET, POST, PUT, PATCH, DELETE"},
            {%{"method" => "GET", "path" => "/orgs"}, "path must be an API path, starting with /api/"},
            {%{"method" => "GET", "path" => "/api/../orgs"}, "path must not contain . or .. segments"},
            {%{"method" => "POST", "path" => "/api/auth_requests"}, "path must not be an auth request"},
            {%{"method" => "POST", "path" => "/api//auth_requests"}, "path must not be an auth request"},
            {%{"method" => "POST", "path" => "/api/users/me/tokens", "body" => "nope"}, "body must be a JSON object"}
          ] do
        conn = post(build_conn(), ~p"/api/auth_requests", params)

        assert json_response(conn, 422) == %{"errors" => %{"detail" => detail}}
      end
    end

    test "creates a token for whoever approves it", %{user: user} do
      {task, code} =
        start_request(%{"method" => "POST", "path" => "/api/users/me/tokens", "body" => %{"note" => "jeff's laptop"}})

      approver(user)
      |> visit(~p"/auth/approve")
      |> fill_in("Code", with: String.downcase(code))
      |> click_button("Continue")
      |> assert_has("dd", text: "POST /api/users/me/tokens")
      |> assert_has("pre", text: "jeff's laptop")
      |> assert_has("dd", text: "nh-test/1.0")
      |> click_button("Approve")
      |> assert_has("h1", text: "Request approved")

      events = await_events(task)

      assert [{"pending", pending}, {"approved", approved}, {"response", response}] = events
      assert pending["code"] == AuthRequests.format_code(code)
      assert pending["verification_uri"] =~ "/auth/approve"
      assert approved == %{"user" => %{"name" => user.name, "email" => user.email}}

      assert %{"status" => 200, "body" => %{"data" => %{"token" => "nhu_" <> _ = token, "email" => email}}} = response
      assert email == user.email

      assert {:ok, %{id: user_id}, %{note: "jeff's laptop"}} = Accounts.fetch_user_by_api_token(token)
      assert user_id == user.id
    end

    test "returns the route's refusal when the approver isn't allowed", %{user2: user2, org: org} do
      {task, code} = start_request(%{"method" => "GET", "path" => "/api/orgs/#{org.name}/users"})

      approver(user2)
      |> visit(~p"/auth/approve")
      |> fill_in("Code", with: code)
      |> click_button("Continue")
      |> click_button("Approve")
      |> assert_has("h1", text: "Request approved, but it failed")

      assert [{"pending", _}, {"approved", _}, {"response", %{"status" => status}}] = await_events(task)
      assert status in [401, 403, 404]
    end

    test "tells the requester when it's denied, without running it", %{user: user} do
      {task, code} = start_request(%{"method" => "POST", "path" => "/api/users/me/tokens"})
      tokens_before = length(Accounts.get_user_api_tokens(user))

      approver(user)
      |> visit(~p"/auth/approve")
      |> fill_in("Code", with: code)
      |> click_button("Continue")
      |> click_button("Deny")
      |> assert_has("h1", text: "Request denied")

      assert [{"pending", _}, {"denied", %{}}] = await_events(task)
      assert length(Accounts.get_user_api_tokens(user)) == tokens_before
    end

    test "can only be decided once", %{user: user, user2: user2} do
      {task, code} = start_request(%{"method" => "POST", "path" => "/api/users/me/tokens"})

      session =
        approver(user)
        |> visit(~p"/auth/approve")
        |> fill_in("Code", with: code)
        |> click_button("Continue")

      approver(user2)
      |> visit(~p"/auth/approve")
      |> fill_in("Code", with: code)
      |> click_button("Continue")
      |> click_button("Deny")

      session
      |> click_button("Approve")
      |> assert_has("[role=alert]", text: "There is no open request with that code")

      assert [{"pending", _}, {"denied", %{}}] = await_events(task)
    end

    test "expires", %{user: user} do
      put_auth_request_config(ttl: 100, heartbeat_interval: 20)

      {task, code} = start_request(%{"method" => "POST", "path" => "/api/users/me/tokens"})

      assert [{"pending", %{"expires_in" => 0}}, {"expired", %{}}] = await_events(task)

      approver(user)
      |> visit(~p"/auth/approve")
      |> fill_in("Code", with: code)
      |> click_button("Continue")
      |> assert_has("[role=alert]", text: "There is no open request with that code")
    end
  end

  describe "the approval page" do
    test "needs a signed in user" do
      build_conn()
      |> visit(~p"/auth/approve")
      |> assert_path(~p"/login")
    end

    test "doesn't find a code that isn't open", %{user: user} do
      approver(user)
      |> visit(~p"/auth/approve")
      |> fill_in("Code", with: "BCDF-GHJK")
      |> click_button("Continue")
      |> assert_has("[role=alert]", text: "There is no open request with that code")
    end
  end

  defp approver(user) do
    build_conn()
    |> Phoenix.ConnTest.init_test_session(%{"user_token" => Accounts.create_user_session_token(user)})
  end

  defp put_auth_request_config(config) do
    previous = Application.get_env(:nerves_hub, AuthRequests)
    Application.put_env(:nerves_hub, AuthRequests, config)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:nerves_hub, AuthRequests, previous),
        else: Application.delete_env(:nerves_hub, AuthRequests)
    end)
  end

  # The stream only returns once the request is decided or expires, so it runs
  # in a task while the test approves it. Its code isn't readable until then,
  # so it is found through the registration the task's process makes.
  defp start_request(params) do
    task =
      Task.async(fn ->
        build_conn()
        |> put_req_header("user-agent", "nh-test/1.0")
        |> post(~p"/api/auth_requests", params)
      end)

    {task, await_code(task.pid, 100)}
  end

  defp await_code(_pid, 0), do: flunk("the auth request was never registered")

  defp await_code(pid, attempts) do
    found =
      Enum.find_value(Group.local_entries(NervesHub.Group), fn
        {:registry, "web", "auth_request/" <> code, ^pid, _meta} -> code
        _ -> nil
      end)

    found ||
      (
        Process.sleep(10)
        await_code(pid, attempts - 1)
      )
  end

  defp await_events(task) do
    conn = Task.await(task)

    assert conn.status == 200
    assert ["text/event-stream" <> _] = get_resp_header(conn, "content-type")

    conn.resp_body
    |> String.split("\n\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, ":"))
    |> Enum.map(fn chunk ->
      ["event: " <> event, "data: " <> data] = String.split(chunk, "\n")
      {event, Jason.decode!(data)}
    end)
  end
end
