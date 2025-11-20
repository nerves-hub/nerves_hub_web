defmodule NervesHubWeb.Live.AccountMFATest do
  alias NervesHub.Fixtures
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts.MFA

  test "enables MFA", %{conn: conn, user: user} do
    conn =
      conn
      |> visit("/account/mfa")
      |> assert_has("button", text: "Enable")
      |> click_button("Enable")
      |> assert_has("h1", text: "TOTP")

    secret =
      conn.view
      |> element(".secret-code h4")
      |> render()
      |> Floki.parse_document!()
      |> Floki.text()
      |> String.replace(~r/\s/, "")
      |> Base.decode32!()

    code = NimbleTOTP.verification_code(secret)

    conn
    |> fill_in("Authentication code", with: code)
    |> submit()
    |> assert_has("button", text: "Disable")

    assert %MFA.UserTOTP{} = MFA.get_user_totp(user)
  end

  test "does not accept invalid code for MFA", %{conn: conn, user: user} do
    conn =
      conn
      |> visit("/account/mfa")
      |> assert_has("button", text: "Enable")
      |> click_button("Enable")
      |> assert_has("h1", text: "TOTP")

    conn
    |> fill_in("Authentication code", with: "123456")
    |> submit()
    |> assert_has(".help-block", text: "invalid code")

    assert is_nil(MFA.get_user_totp(user))
  end

  test "shows backup codes when MFA configured", %{conn: conn, user: user} do
    totp = Fixtures.user_totp_fixture(%{user_id: user.id})

    conn =
      conn
      |> visit("/account/mfa")
      |> click_link("Show Backup Codes")
      |> assert_has("span", text: "Hide Backup Codes")

    Enum.each(totp.backup_codes, fn code ->
      assert_has(conn, ".backup-code", text: code.code)
    end)

    conn =
      conn
      |> click_link("Hide Backup Codes")
      |> assert_has("a", text: "Show Backup Codes")

    Enum.each(totp.backup_codes, fn code ->
      refute_has(conn, ".backup-code", text: code.code)
    end)
  end

  test "disables MFA", %{conn: conn, user: user} do
    Fixtures.user_totp_fixture(%{user_id: user.id})

    conn
    |> visit("/account/mfa")
    |> click_button("Disable")
    |> assert_has("button", text: "Enable")

    assert is_nil(MFA.get_user_totp(user))
  end
end
