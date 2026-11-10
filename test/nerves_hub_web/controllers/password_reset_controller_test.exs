defmodule NervesHubWeb.PasswordResetControllerTest do
  use NervesHubWeb.ConnCase, async: true

  import NervesHub.Support.Emails
  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserToken
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  describe "new password_reset" do
    test "renders form", %{conn: conn} do
      conn = get(conn, Routes.password_reset_path(conn, :new))
      assert html_response(conn, 200) =~ "Forgot your password?"
    end
  end

  describe "create password_reset" do
    setup [:create_user]

    test "with valid params", %{conn: conn, user: user} do
      params = %{"user" => %{"email" => user.email}}

      reset_conn = post(conn, Routes.password_reset_path(conn, :create), params)

      html = html_response(reset_conn, 200)
      assert html =~ "Check your email"
      assert html =~ user.email
      assert html =~ "a reset link is on its way."

      send_queued_emails()

      assert_email_sent(subject: "NervesHub: Reset your password")
    end

    test "with invalid params", %{conn: conn} do
      params = %{}

      reset_conn = post(conn, Routes.password_reset_path(conn, :create), params)
      assert html_response(reset_conn, 200) =~ "You must enter an email address."
    end
  end

  describe "reset password" do
    setup [:create_user]

    test "new_password_form with invalid token", %{conn: conn} do
      reset_conn = get(conn, Routes.password_reset_path(conn, :edit, "not a good token"))

      assert redirected_to(reset_conn) == ~p"/password-reset"

      # the request form says why, rather than a toast on the sign-in page
      form_conn = reset_conn |> recycle() |> get(~p"/password-reset")
      html = html_response(form_conn, 200)
      assert html =~ "Get a new reset link"
      assert html =~ "That reset link no longer works"
    end

    test "new_password_form with valid token", %{conn: conn, user: user} do
      {encoded_token, user_token} = UserToken.build_hashed_token(user, "reset_password", nil)
      Repo.insert!(user_token)

      reset_conn = get(conn, Routes.password_reset_path(conn, :edit, encoded_token))

      assert html_response(reset_conn, 200) =~ "Choose a new password"
    end

    test "with valid params", %{conn: conn, user: user} do
      params = %{
        "user" => %{"password" => "new password", "password_confirmation" => "new password"}
      }

      {encoded_token, user_token} = UserToken.build_hashed_token(user, "reset_password", nil)
      Repo.insert!(user_token)

      reset_conn = put(conn, Routes.password_reset_path(conn, :update, encoded_token), params)
      assert redirected_to(reset_conn) == ~p"/orgs"

      # enforce side effect
      {:ok, updated_user} = Accounts.get_user(user.id)
      refute updated_user.password_hash == user.password_hash

      # check token is expired
      second_params = %{"user" => %{"password" => "newer password"}}
      put(conn, Routes.password_reset_path(conn, :update, encoded_token), second_params)
      {:ok, second_updated_user} = Accounts.get_user(user.id)
      assert second_updated_user.password_hash == updated_user.password_hash
    end

    # A page or console already open would otherwise keep working until its
    # socket reconnected
    test "closes the pages and consoles already open", %{conn: conn, user: user} do
      signed_in = post(build_conn(), ~p"/login", %{"user" => %{"email" => user.email, "password" => "test_password"}})
      live_socket_id = get_session(signed_in, :live_socket_id)
      api_socket_id = "api_socket:#{user.id}"
      :ok = NervesHubWeb.Endpoint.subscribe(live_socket_id)
      :ok = NervesHubWeb.Endpoint.subscribe(api_socket_id)

      {encoded_token, user_token} = UserToken.build_hashed_token(user, "reset_password", nil)
      Repo.insert!(user_token)

      params = %{"user" => %{"password" => "new password", "password_confirmation" => "new password"}}
      put(conn, Routes.password_reset_path(conn, :update, encoded_token), params)

      assert_receive %Broadcast{topic: ^live_socket_id, event: "disconnect"}
      assert_receive %Broadcast{topic: ^api_socket_id, event: "disconnect"}
    end

    # The reset link went to the account's address, which proves it's theirs
    test "confirms an unconfirmed account", %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{name: "Jane", email: "jane@person.com", password: "old password"})
      params = %{"user" => %{"password" => "new password", "password_confirmation" => "new password"}}

      {encoded_token, user_token} = UserToken.build_hashed_token(user, "reset_password", nil)
      Repo.insert!(user_token)

      reset_conn = put(conn, Routes.password_reset_path(conn, :update, encoded_token), params)
      assert redirected_to(reset_conn) == ~p"/orgs"

      refute is_nil(Repo.reload(user).confirmed_at)
    end

    test "with invalid params", %{conn: conn, user: user} do
      params = %{"user" => %{"password" => ""}}

      {encoded_token, user_token} = UserToken.build_hashed_token(user, "reset_password", nil)
      Repo.insert!(user_token)

      reset_conn = put(conn, Routes.password_reset_path(conn, :update, encoded_token), params)
      assert html_response(reset_conn, 200) =~ "can&#39;t be blank"

      # enforce side effect
      {:ok, updated_user} = Accounts.get_user(user.id)
      assert updated_user.password_hash == user.password_hash
    end

    test "with invalid token", %{conn: conn, user: user} do
      params = %{"user" => %{"email" => user.email, "password" => "new password"}}

      # a well-formed token that was never stored
      {bad_token, _user_token} = UserToken.build_hashed_token(user, "reset_password", nil)

      reset_conn = put(conn, Routes.password_reset_path(conn, :update, bad_token), params)
      assert redirected_to(reset_conn) == ~p"/password-reset"

      # enforce side effect
      {:ok, updated_user} = Accounts.get_user(user.id)
      assert updated_user.password_hash == user.password_hash
    end
  end

  defp create_user(_) do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    {:ok, user: user, org: org}
  end
end
