defmodule NervesHubWWWWeb.PasswordResetControllerTest do
  use NervesHubWWWWeb.ConnCase, async: true
  use Bamboo.Test

  alias NervesHubWebCore.Fixtures
  alias NervesHubWebCore.Accounts

  describe "new password_reset" do
    test "renders form", %{conn: conn} do
      conn = get(conn, Routes.password_reset_path(conn, :new))
      assert html_response(conn, 200) =~ "Reset Password"
    end
  end

  describe "create password_reset" do
    setup [:create_user]

    test "with valid params", %{conn: conn, user: user} do
      params = %{"password_reset" => %{"email" => user.email}}

      reset_conn = post(conn, Routes.password_reset_path(conn, :create), params)

      assert redirected_to(reset_conn) == Routes.session_path(reset_conn, :new)

      {:ok, updated_user} = Accounts.get_user(user.id)
      assert_delivered_email(NervesHubWebCore.Accounts.Email.forgot_password(updated_user))
    end

    test "with invalid params", %{conn: conn} do
      params = %{}

      reset_conn = post(conn, Routes.password_reset_path(conn, :create), params)
      assert html_response(reset_conn, 200) =~ "You must enter an email address."
    end
  end

  describe "reset password" do
    setup [:create_user]

    test "new_password_form with invalid token", %{conn: conn, user: user} do
      params = %{"user" => %{"email" => user.email}}

      reset_conn =
        get(
          conn,
          Routes.password_reset_path(conn, :new_password_form, "not a good token"),
          params
        )

      assert redirected_to(reset_conn) == Routes.session_path(reset_conn, :new)
    end

    test "new_password_form with valid token", %{conn: conn, user: user} do
      params = %{"user" => %{"email" => user.email}}

      token =
        Accounts.update_password_reset_token(user.email)
        |> elem(1)
        |> Map.get(:password_reset_token)

      reset_conn = get(conn, Routes.password_reset_path(conn, :new_password_form, token), params)

      assert html_response(reset_conn, 200) =~ "New Password"
    end

    test "with valid params", %{conn: conn, user: user} do
      params = %{
        "user" => %{"password" => "new password", "password_confirmation" => "new password"}
      }

      token =
        Accounts.update_password_reset_token(user.email)
        |> elem(1)
        |> Map.get(:password_reset_token)

      reset_conn = put(conn, Routes.password_reset_path(conn, :reset, token), params)
      assert redirected_to(reset_conn) == Routes.session_path(reset_conn, :new)

      # enforce side effect
      {:ok, updated_user} = Accounts.get_user(user.id)
      refute updated_user.password_hash == user.password_hash

      # check token is expired
      second_params = %{"user" => %{"password" => "newer password"}}
      put(conn, Routes.password_reset_path(conn, :reset, token), second_params)
      {:ok, second_updated_user} = Accounts.get_user(user.id)
      assert second_updated_user.password_hash == updated_user.password_hash
    end

    test "with invalid params", %{conn: conn, user: user} do
      params = %{"user" => %{"password" => ""}}

      token =
        Accounts.update_password_reset_token(user.email)
        |> elem(1)
        |> Map.get(:password_reset_token)

      reset_conn = put(conn, Routes.password_reset_path(conn, :reset, token), params)
      assert html_response(reset_conn, 200) =~ "You must provide a new password."

      # enforce side effect
      {:ok, updated_user} = Accounts.get_user(user.id)
      assert updated_user.password_hash == user.password_hash
    end

    test "with invalid token", %{conn: conn, user: user} do
      params = %{"user" => %{"email" => user.email, "password" => "new password"}}

      bad_token = Ecto.UUID.bingenerate()

      reset_conn = put(conn, Routes.password_reset_path(conn, :reset, bad_token), params)
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
