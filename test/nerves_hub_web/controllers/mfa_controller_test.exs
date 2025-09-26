defmodule NervesHubWeb.MFAControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts.MFA
  alias NervesHub.Fixtures

  describe "new/2" do
    test "renders MFA verification form when user_id is in session", %{user: user} do
      build_conn()
      |> init_test_session(mfa_user_id: user.id)
      |> visit(~p"/mfa")
      |> assert_has("h1", with: "Authentication Code")
    end

    test "redirects to login when no user_id in session" do
      session = build_conn() |> visit(~p"/mfa")
      assert_path(session, ~p"/login")

      assert Phoenix.Flash.get(session.conn.assigns.flash, :error) ==
               "Invalid session. Please log in again."
    end
  end

  describe "create/2" do
    setup %{user: user} do
      user_totp = Fixtures.user_totp_fixture(%{user_id: user.id})
      {:ok, %{user_totp: user_totp}}
    end

    test "logs in user with valid TOTP code", %{user: user} do
      user_totp = MFA.get_user_totp(user)
      valid_code = NimbleTOTP.verification_code(user_totp.secret)

      build_conn()
      |> init_test_session(mfa_user_id: user.id, mfa_user_params: %{"remember_me" => "true"})
      |> visit(~p"/mfa")
      |> fill_in("Authentication Code", with: valid_code)
      |> submit()
      |> assert_path(~p"/orgs")
    end

    test "logs in user with valid backup code", %{user: user} do
      user_totp = MFA.get_user_totp(user)
      backup_code = List.first(user_totp.backup_codes).code

      session =
        build_conn()
        |> init_test_session(mfa_user_id: user.id, mfa_user_params: %{})
        |> visit(~p"/mfa")
        |> fill_in("Authentication Code", with: backup_code)
        |> submit()

      assert_path(session, ~p"/orgs")

      # Check that flash message about remaining backup codes is shown
      flash_message = Phoenix.Flash.get(session.conn.assigns.flash, :info)
      assert flash_message =~ "Backup code used"
      assert flash_message =~ "backup codes remaining"
    end

    test "shows error with invalid TOTP code", %{user: user} do
      session =
        build_conn()
        |> init_test_session(%{mfa_user_id: user.id})
        |> visit(~p"/mfa")
        |> fill_in("Authentication Code", with: "123456")
        |> submit()

      assert_has(session, "p", with: "Invalid code")

      assert get_session(session.conn, :mfa_user_id) == user.id
    end

    test "redirects to login when no user_id in session" do
      conn =
        build_conn()
        |> post(~p"/mfa", %{
          "mfa" => %{"code" => "123456"}
        })

      assert redirected_to(conn) == "/login"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid session. Please log in again."
    end
  end
end
