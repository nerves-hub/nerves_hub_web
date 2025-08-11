defmodule NervesHubWeb.PasswordResetControllerTest do
  use NervesHubWeb.ConnCase, async: true

  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserToken
  alias NervesHub.Fixtures

  alias NervesHub.Repo

  describe "new password_reset" do
    test "renders form", %{conn: conn} do
      conn = get(conn, Routes.password_reset_path(conn, :new))
      assert html_response(conn, 200) =~ "Reset your password"
    end
  end

  describe "create password_reset" do
    setup [:create_user]

    test "with valid params", %{conn: conn, user: user} do
      params = %{"user" => %{"email" => user.email}}

      reset_conn = post(conn, Routes.password_reset_path(conn, :create), params)

      assert html_response(reset_conn, 200) =~
               "If your email is recognized, you will receive instructions to reset your password shortly."

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

      assert redirected_to(reset_conn) == Routes.session_path(reset_conn, :new)
    end

    test "new_password_form with valid token", %{conn: conn, user: user} do
      {encoded_token, user_token} = UserToken.build_hashed_token(user, "reset_password", nil)
      Repo.insert!(user_token)

      reset_conn = get(conn, Routes.password_reset_path(conn, :edit, encoded_token))

      assert html_response(reset_conn, 200) =~ "Reset your password"
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

      bad_token = Ecto.UUID.bingenerate()

      reset_conn = put(conn, Routes.password_reset_path(conn, :update, bad_token), params)
      assert redirected_to(reset_conn) == Routes.session_path(reset_conn, :new)

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
