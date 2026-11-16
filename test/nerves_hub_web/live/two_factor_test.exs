defmodule NervesHubWeb.Live.TwoFactorTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts
  alias NervesHub.Accounts.TwoFactor
  alias NervesHub.Fixtures

  defp signed_in(user) do
    init_test_session(build_conn(), %{"user_token" => Accounts.create_user_session_token(user)})
  end

  describe "account page" do
    test "sets up an authenticator app and shows the recovery codes once", %{conn: conn, user: user} do
      session =
        conn
        |> visit(~p"/account/two-factor")
        |> assert_has("#two-factor-off")
        |> click_button("Set up two-factor authentication")
        |> assert_has("#two-factor-qr-code svg")

      secret =
        session
        |> unwrap(fn view ->
          [_, text] = Regex.run(~r/>([^<]+)</, view |> element("#two-factor-secret") |> render())
          send(self(), {:secret, text})
          render(view)
        end)
        |> then(fn _ ->
          assert_received {:secret, text}
          text |> String.replace(" ", "") |> Base.decode32!(padding: false)
        end)

      session
      |> fill_in("Code from the app", with: NimbleTOTP.verification_code(secret))
      |> fill_in("Your password", with: "test_password")
      |> click_button("Turn on")
      |> assert_has("#recovery-codes li", count: 10)
      |> click_button("I've saved them")
      |> refute_has("#recovery-codes")
      |> assert_has("#two-factor-on", text: "10 recovery codes left")

      assert TwoFactor.enabled?(user)
    end

    test "won't turn on without the password", %{conn: conn, user: user} do
      conn
      |> visit(~p"/account/two-factor")
      |> click_button("Set up two-factor authentication")
      |> fill_in("Code from the app", with: "123456")
      |> fill_in("Your password", with: "not it")
      |> click_button("Turn on")
      |> assert_has("#two-factor-error", text: "That password isn't right.")

      refute TwoFactor.enabled?(user)
    end

    test "turns off with a code", %{conn: conn, user: user} do
      %{secret: secret} = Fixtures.two_factor_fixture(user)

      conn
      |> visit(~p"/account/two-factor")
      |> within("#two-factor-disable-form", fn session ->
        session
        |> fill_in("Code from the app, or a recovery code", with: "000000")
        |> click_button("Turn off")
      end)
      |> assert_has("#two-factor-error", text: "That code didn't work")
      |> within("#two-factor-disable-form", fn session ->
        session
        |> fill_in("Code from the app, or a recovery code", with: Fixtures.next_totp_code(secret))
        |> click_button("Turn off")
      end)
      |> assert_has("#two-factor-off")

      refute TwoFactor.enabled?(user)
    end

    test "makes new recovery codes", %{conn: conn, user: user} do
      %{recovery_codes: [code | _]} = Fixtures.two_factor_fixture(user)

      conn
      |> visit(~p"/account/two-factor")
      |> within("#two-factor-regenerate-form", fn session ->
        session
        |> fill_in("Code from the app, or a recovery code", with: code)
        |> click_button("Make new codes")
      end)
      |> assert_has("#recovery-codes li", count: 10)
    end

    test "the account page links to it", %{conn: conn} do
      conn
      |> visit(~p"/account")
      |> assert_has("#two-factor-summary", text: "Off")
      |> click_link("Set up")
      |> assert_path(~p"/account/two-factor")
    end
  end

  describe "an organization that requires it" do
    setup %{user: user, org: org} do
      Fixtures.two_factor_fixture(user)
      {:ok, org} = TwoFactor.set_org_requirement(org, user, true)

      member = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, member, %{role: :manage})

      %{org: org, member: member}
    end

    test "sends a member without it to set it up", %{org: org, member: member} do
      member
      |> signed_in()
      |> visit(~p"/org/#{org}")
      |> assert_path(~p"/account/two-factor")
      |> assert_has("#two-factor-required", text: "#{org.name} requires two-factor authentication")
    end

    test "stops them at the org's controller routes too", %{org: org, member: member, product: product} do
      conn = get(signed_in(member), ~p"/org/#{org}/#{product}/devices/export")

      assert redirected_to(conn) == ~p"/account/two-factor"
    end

    test "lets them in once they turn it on", %{org: org, member: member} do
      Fixtures.two_factor_fixture(member)

      member
      |> signed_in()
      |> visit(~p"/org/#{org}")
      |> assert_path(~p"/org/#{org}")
    end

    test "refuses them in the API", %{org: org, member: member} do
      token = Accounts.create_user_api_token(member, "test-token")

      conn =
        build_conn()
        |> put_req_header("authorization", "token #{token}")
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/orgs/#{org}/products")

      assert %{"errors" => %{"detail" => detail}} = json_response(conn, 403)
      assert detail =~ "requires two-factor authentication"
    end

    test "warns them before they turn it off", %{org: org, member: member} do
      Fixtures.two_factor_fixture(member)

      member
      |> signed_in()
      |> visit(~p"/account/two-factor")
      |> assert_has("#two-factor-disable-warning", text: org.name)
    end
  end

  describe "organization settings" do
    test "an admin without it can't require it", %{conn: conn, org: org} do
      conn
      |> visit(~p"/org/#{org}/settings")
      |> assert_has("#require_two_factor[disabled]")
      |> assert_has("#require_two_factor_hint a", text: "Turn it on for your own account")
    end

    test "an admin with it can require it, and sees who would be turned away", %{conn: conn, org: org, user: user} do
      Fixtures.two_factor_fixture(user)
      member = Fixtures.user_fixture(%{name: "Ringo"})
      {:ok, _} = Accounts.add_org_user(org, member, %{role: :view})

      conn
      |> visit(~p"/org/#{org}/settings")
      |> assert_has("#members-without-two-factor", text: "Ringo")
      |> check("Require two-factor authentication for every member")
      |> within("#org-two-factor-form", &click_button(&1, "Save"))
      |> assert_has("div", text: "Members now need two-factor authentication")

      assert Accounts.get_org!(org.id).require_two_factor
    end
  end
end
