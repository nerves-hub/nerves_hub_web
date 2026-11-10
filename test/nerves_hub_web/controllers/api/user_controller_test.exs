defmodule NervesHubWeb.API.UserControllerTest do
  use NervesHubWeb.APIConnCase, async: false

  import NervesHub.Support.PhoenixTestAssertions
  import PhoenixTest, except: [assert_has: 3, assert_has: 4, refute_has: 3, refute_has: 4]

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHub.PlugAttack.Storage, as: PlugAttackStorage
  alias NervesHub.Repo
  alias PlugAttack.Storage.Ets, as: PlugAttackEts

  test "me", %{conn: conn, user: user} do
    conn = get(conn, Routes.api_user_path(conn, :me))

    assert json_response(conn, 200)["data"] == %{
             "name" => user.name,
             "email" => user.email
           }
  end

  test "authenticate existing accounts" do
    password = "1234567891011"

    user =
      Fixtures.user_fixture(%{
        name: "New User",
        email: "account_test@test.com",
        password: password
      })

    conn = build_conn()
    conn = post(conn, Routes.api_user_path(conn, :auth), %{email: user.email, password: password})

    resp = json_response(conn, 200)
    assert resp["data"]["name"] == user.name
    assert resp["data"]["email"] == user.email
    assert "nhu_" <> _ = resp["data"]["token"]
  end

  test "refuses an account whose email isn't confirmed" do
    {:ok, user} =
      Accounts.create_user(%{name: "New User", email: "account_test@test.com", password: "1234567891011"})

    conn = build_conn()
    conn = post(conn, Routes.api_user_path(conn, :auth), %{email: user.email, password: "1234567891011"})

    assert json_response(conn, 401)["errors"] == %{
             "detail" =>
               "Confirm your email address before signing in. Signing in on the web sends a new confirmation link."
           }
  end

  test "authentication shouldn't blow up if the password isn't included" do
    user =
      Fixtures.user_fixture(%{
        name: "New User",
        email: "account_test@test.com",
        password: "1234567891011"
      })

    conn = build_conn()
    conn = post(conn, Routes.api_user_path(conn, :auth), %{email: user.email})

    assert json_response(conn, 401)["errors"] == %{
             "detail" => "Authentication failed, please check your username and password and try again."
           }
  end

  test "authentication shouldn't blow up if the password is nil" do
    user =
      Fixtures.user_fixture(%{
        name: "New User",
        email: "account_test@test.com",
        password: "1234567891011"
      })

    conn = build_conn()
    conn = post(conn, Routes.api_user_path(conn, :auth), %{email: user.email, password: nil})

    assert json_response(conn, 401)["errors"] == %{
             "detail" => "Authentication failed, please check your username and password and try again."
           }
  end

  test "authentication shouldn't blow up if the password hash is nil" do
    user =
      Fixtures.user_fixture(%{
        name: "New User",
        email: "account_test@test.com",
        password: "1234567891011"
      })

    user = Repo.update!(Ecto.Changeset.change(user, password_hash: nil))

    conn = build_conn()
    conn = post(conn, Routes.api_user_path(conn, :auth), %{email: user.email, password: "1234567891011"})

    assert json_response(conn, 401)["errors"] == %{
             "detail" => "Authentication failed, please check your username and password and try again."
           }
  end

  test "create token for existing account when authenticated" do
    password = "1234567891011"

    user =
      Fixtures.user_fixture(%{
        name: "New User",
        email: "account_test@test.com",
        password: password
      })

    conn = build_conn()

    conn =
      post(conn, Routes.api_user_path(conn, :login), %{
        email: user.email,
        password: password,
        note: "tester"
      })

    resp = json_response(conn, 200)
    assert resp["data"]["name"] == user.name
    assert resp["data"]["email"] == user.email
    assert "nhu_" <> _ = resp["data"]["token"]
  end

  describe "cli session auth exchange" do
    setup do
      PlugAttackEts.clean(PlugAttackStorage)
      on_exit(fn -> PlugAttackEts.clean(PlugAttackStorage) end)
    end

    test "created successfully", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/cli_session")

      data = json_response(conn, 200)["data"]

      assert data["token"] =~ ~r/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/
      assert data["url"] == "http://localhost:1234/auth/cli"
      assert data["confirmation_code"] in 10_000_000..99_999_999
    end

    test "checking the status of an uncompleted session returns :waiting", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/cli_session")

      token = json_response(conn, 200)["data"]["token"]

      conn = get(conn, ~p"/api/auth/cli_session/#{token}")
      data = json_response(conn, 200)["data"]

      assert data["status"] == "waiting"
    end

    test "checking the status of a completed session returns :ready and the users auth token", %{conn: conn, user: user} do
      conn = post(conn, ~p"/api/auth/cli_session")

      token = json_response(conn, 200)["data"]["token"]

      conn = get(conn, ~p"/api/auth/cli_session/#{token}")
      data = json_response(conn, 200)["data"]

      assert data["status"] == "waiting"

      :ok = NervesHub.Accounts.verify_cli_session_token(user, token)

      conn = get(conn, ~p"/api/auth/cli_session/#{token}")
      data = json_response(conn, 200)["data"]

      assert data["status"] == "ready"
      assert data["user_token"] =~ "nhu_"
    end

    test "the login is confirmed by typing in its code, and the CLI collects a token", %{conn: conn, user: user} do
      %{"token" => token, "confirmation_code" => code} = start_cli_login(conn)

      user
      |> signed_in()
      |> visit(~p"/auth/cli")
      |> assert_has("h1", text: "Sign in to the CLI")
      |> fill_in("Code", with: spaced(code))
      |> click_button("Continue")
      |> assert_has("h1", text: "Confirm the CLI sign-in")
      |> assert_has("#cli_requested_at")
      |> assert_has("#cli_requested_from", text: "127.0.0.1")
      |> assert_has("#cli_note", text: "nh 0.1.2 (build-01)")
      |> refute_has("#cli_other_address")
      |> click_button("Confirm sign in")
      |> assert_path(~p"/auth/cli/confirmed")
      |> assert_has("h1", text: "You're signed in to the CLI")

      data = conn |> get(~p"/api/auth/cli_session/#{token}") |> json_response(200) |> Map.fetch!("data")

      assert data["status"] == "ready"
      assert data["user_token"] =~ "nhu_"
    end

    test "the token the CLI polls with can't find or confirm the login", %{conn: conn, user: user} do
      %{"token" => token} = start_cli_login(conn)

      user
      |> signed_in()
      |> visit(~p"/auth/cli")
      |> fill_in("Code", with: token)
      |> click_button("Continue")
      |> assert_has("[role=alert]", text: "match a sign-in waiting to be confirmed")

      response = user |> signed_in() |> post(~p"/auth/cli/confirm", %{"code" => token}) |> html_response(200)

      assert response =~ "match a sign-in waiting to be confirmed"
      assert waiting?(conn, token)
    end

    test "a wrong code confirms nothing", %{conn: conn, user: user} do
      %{"token" => token, "confirmation_code" => code} = start_cli_login(conn)
      wrong = Integer.to_string(another_code(code))

      user
      |> signed_in()
      |> visit(~p"/auth/cli")
      |> fill_in("Code", with: wrong)
      |> click_button("Continue")
      |> assert_has("[role=alert]", text: "match a sign-in waiting to be confirmed")

      response = user |> signed_in() |> post(~p"/auth/cli/confirm", %{"code" => wrong}) |> html_response(200)

      assert response =~ "match a sign-in waiting to be confirmed"
      assert waiting?(conn, token)
    end

    test "the confirmation page points out a CLI at another address", %{conn: conn, user: user} do
      %{"confirmation_code" => code} =
        conn
        |> put_req_header("x-forwarded-for", "203.0.113.9")
        |> start_cli_login()

      user
      |> signed_in()
      |> visit(~p"/auth/cli")
      |> fill_in("Code", with: Integer.to_string(code))
      |> click_button("Continue")
      |> assert_has("#cli_requested_from", text: "203.0.113.9")
      |> assert_has("#cli_other_address", text: "127.0.0.1")
      |> assert_has("#cli_other_address", text: "don't confirm it")
    end

    # A login used to come with a link to /auth/cli/<token>, and opening it while
    # signed in was one click away from confirming it.
    test "a link can't find or confirm a login", %{conn: conn, user: user} do
      %{"token" => token, "confirmation_code" => code} = start_cli_login(conn)
      api_tokens = NervesHub.Accounts.get_user_api_tokens(user)

      assert user |> signed_in() |> get("/auth/cli/#{token}") |> response(404)
      assert user |> signed_in() |> post("/auth/cli/#{token}") |> response(404)

      page = user |> signed_in() |> get("/auth/cli?code=#{code}&token=#{token}") |> html_response(200)

      assert page =~ "Sign in to the CLI"
      refute page =~ Integer.to_string(code)
      refute page =~ token

      assert waiting?(conn, token)
      assert NervesHub.Accounts.get_user_api_tokens(user) == api_tokens
    end

    test "a code that isn't text finds nothing", %{conn: conn, user: user} do
      %{"token" => token} = start_cli_login(conn)

      for path <- [~p"/auth/cli", ~p"/auth/cli/confirm"], code <- [["1"], %{"code" => "1"}] do
        assert user |> signed_in() |> post(path, %{"code" => code}) |> html_response(200) =~
                 "match a sign-in waiting to be confirmed"
      end

      assert waiting?(conn, token)
    end

    test "a confirmed login's code only takes the person who confirmed it back to the confirmation", %{
      conn: conn,
      user: user,
      user2: other_user
    } do
      %{"confirmation_code" => code} = start_cli_login(conn)

      user
      |> signed_in()
      |> visit(~p"/auth/cli")
      |> fill_in("Code", with: Integer.to_string(code))
      |> click_button("Continue")
      |> click_button("Confirm sign in")
      |> assert_path(~p"/auth/cli/confirmed")

      user
      |> signed_in()
      |> visit(~p"/auth/cli")
      |> fill_in("Code", with: Integer.to_string(code))
      |> click_button("Continue")
      |> assert_path(~p"/auth/cli/confirmed")
      |> assert_has("h1", text: "You're signed in to the CLI")

      other_user
      |> signed_in()
      |> visit(~p"/auth/cli")
      |> fill_in("Code", with: Integer.to_string(code))
      |> click_button("Continue")
      |> assert_has("[role=alert]", text: "match a sign-in waiting to be confirmed")
    end

    test "each person can try ten codes every ten minutes", %{conn: conn, user: user, user2: other_user} do
      %{"token" => token, "confirmation_code" => code} = start_cli_login(conn)
      wrong = Integer.to_string(another_code(code))

      for _ <- 1..10 do
        assert user |> signed_in() |> post(~p"/auth/cli", %{"code" => wrong}) |> html_response(200) =~
                 "match a sign-in waiting to be confirmed"
      end

      for path <- [~p"/auth/cli", ~p"/auth/cli/confirm"] do
        assert user |> signed_in() |> post(path, %{"code" => Integer.to_string(code)}) |> html_response(200) =~
                 "Too many codes tried"
      end

      assert waiting?(conn, token)

      assert other_user
             |> signed_in()
             |> post(~p"/auth/cli", %{"code" => Integer.to_string(code)})
             |> html_response(200) =~
               "Confirm the CLI sign-in"
    end

    test "cannot share the same token", %{conn: conn} do
      Mimic.expect(Ecto.UUID, :generate, 2, fn -> "unique_token" end)

      conn = post(conn, ~p"/api/auth/cli_session")

      token = json_response(conn, 200)["data"]["token"]
      assert token =~ "unique_token"

      assert_raise(NervesHubWeb.InvalidRequestError, fn ->
        post(conn, ~p"/api/auth/cli_session")
      end)
    end

    test "cannot verify tokens which are already verified", %{conn: conn, user: user, user2: user2} do
      conn = post(conn, ~p"/api/auth/cli_session")

      token = json_response(conn, 200)["data"]["token"]

      conn = get(conn, ~p"/api/auth/cli_session/#{token}")
      data = json_response(conn, 200)["data"]

      assert data["status"] == "waiting"

      :ok = NervesHub.Accounts.verify_cli_session_token(user, token)

      assert {:error, :already_verified} = NervesHub.Accounts.verify_cli_session_token(user2, token)
    end

    test "a NervesHubWeb.NotFoundError is raised when a verified tokens status is checked again", %{
      conn: conn,
      user: user
    } do
      conn = post(conn, ~p"/api/auth/cli_session")

      token = json_response(conn, 200)["data"]["token"]

      conn = get(conn, ~p"/api/auth/cli_session/#{token}")
      data = json_response(conn, 200)["data"]

      assert data["status"] == "waiting"

      :ok = NervesHub.Accounts.verify_cli_session_token(user, token)

      conn = get(conn, ~p"/api/auth/cli_session/#{token}")
      data = json_response(conn, 200)["data"]

      assert data["status"] == "ready"
      assert data["user_token"] =~ "nhu_"

      assert_raise(NervesHubWeb.NotFoundError, fn ->
        get(conn, ~p"/api/auth/cli_session/#{token}")
      end)
    end

    # nh polls every two seconds, which is the whole allowance, so starting the
    # login can't count towards it.
    test "polling is limited to thirty a minute, not counting the start of the login", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/cli_session")

      token = json_response(conn, 200)["data"]["token"]

      for _ <- 1..30 do
        conn = get(conn, ~p"/api/auth/cli_session/#{token}")
        data = json_response(conn, 200)["data"]

        assert data["status"] == "waiting"
      end

      conn = get(conn, ~p"/api/auth/cli_session/#{token}")
      assert response(conn, 403) =~ "Forbidden"
    end

    test "each address can start ten logins every ten minutes", %{conn: conn} do
      logins = for _ <- 1..10, do: start_cli_login(conn)

      assert conn |> post(~p"/api/auth/cli_session") |> response(403) =~ "Forbidden"

      # The logins already started still wait, and another address can start one.
      assert Enum.all?(logins, &waiting?(conn, &1["token"]))
      assert %{"token" => _} = start_cli_login(%{conn | remote_ip: {198, 51, 100, 7}})
    end

    # Postgres can't store a NUL, and a right-to-left override reverses the
    # text after it on the confirmation page.
    test "a note that won't fit on the API token, or isn't printable, is refused", %{conn: conn} do
      for note <- [String.duplicate("a", 256), %{"note" => "nh"}, <<"nh", 0>>, "nh \u202Egpj.exe"] do
        assert_raise NervesHubWeb.InvalidRequestError, ~r/note must be at most 255 characters of printable text/, fn ->
          post(conn, ~p"/api/auth/cli_session", %{"note" => note})
        end
      end
    end
  end

  defp start_cli_login(conn) do
    conn
    |> post(~p"/api/auth/cli_session", %{"note" => "nh 0.1.2 (build-01)"})
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp signed_in(user) do
    init_test_session(build_conn(), %{"user_token" => NervesHub.Accounts.create_user_session_token(user)})
  end

  # As nh prints it.
  defp spaced(code), do: code |> Integer.to_string() |> String.graphemes() |> Enum.join(" ")

  # A code no login is waiting with.
  defp another_code(99_999_999), do: 10_000_000
  defp another_code(code), do: code + 1

  defp waiting?(conn, token) do
    conn
    |> get(~p"/api/auth/cli_session/#{token}")
    |> json_response(200)
    |> get_in(["data", "status"])
    |> Kernel.==("waiting")
  end
end
