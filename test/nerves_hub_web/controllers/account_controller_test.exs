defmodule NervesHubWeb.AccountControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserToken

  alias NervesHub.Repo

  describe "new" do
    test "renders registration form when registrations are enabled" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      build_conn()
      |> visit(~p"/register")
      |> assert_has("h1", with: "Create a new account")
    end

    test "redirects to /login with a flash when registrations are disabled" do
      Application.put_env(:nerves_hub, :open_for_registrations, false)

      build_conn()
      |> visit(~p"/register")
      |> assert_path(~p"/login")
    end
  end

  describe "create" do
    test "registers new account" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      build_conn()
      |> visit(~p"/register")
      |> assert_has("h1", with: "Create a new account")
      |> fill_in("Name", with: "Sgt Pepper")
      |> fill_in("Email address", with: "sgtpepper@geocities.com")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_has("h1", with: "Please confirm your email")
      |> assert_has("p", with: "Your new account was created successfully!")

      platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

      assert_email_sent(fn email ->
        assert email.subject == "#{platform_name}: Confirm your account"
        assert to_string(email.text_body) =~ "Thanks for creating an account with NervesHub."
        assert email.html_body =~ "Thanks for creating an account with NervesHub."
      end)
    end

    test "requires name, email, and password, to create a new account" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      build_conn()
      |> visit(~p"/register")
      |> assert_has("h1", with: "Create a new account")
      |> fill_in("Name", with: "")
      |> fill_in("Email address", with: "")
      |> fill_in("Password", with: "")
      |> submit()
      |> assert_path(~p"/register")
      |> assert_has("p", with: "can't be blank", times: 3)

      refute_email_sent()
    end

    test "confirm account and be logged in" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      params = %{
        name: "Sgt Pepper",
        email: "sgtpepper@geocities.com",
        password: "JohnRingoPaulGeorge"
      }

      {:ok, user} = Accounts.create_user(params)

      {encoded_token, user_token} = UserToken.build_hashed_token(user, "confirm", nil)
      Repo.insert!(user_token)

      build_conn()
      |> visit(~p"/confirm/#{encoded_token}")
      |> assert_path(~p"/orgs")

      platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

      assert_email_sent(fn email ->
        assert email.subject == "#{platform_name}: Welcome Sgt Pepper!"
        assert to_string(email.text_body) =~ "Welcome to #{platform_name}!"
        assert email.html_body =~ "Welcome to #{platform_name}!"
      end)
    end

    test "send new confirm account email if the token is older than 1 day" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      params = %{
        name: "Sgt Pepper",
        email: "sgtpepper@geocities.com",
        password: "JohnRingoPaulGeorge"
      }

      {:ok, user} = Accounts.create_user(params)

      {encoded_token, user_token} = UserToken.build_hashed_token(user, "confirm", nil)

      twenty_five_hours_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-25, :hour)
        |> NaiveDateTime.truncate(:second)

      user_token
      |> Map.put(:inserted_at, twenty_five_hours_ago)
      |> Repo.insert!()

      build_conn()
      |> visit(~p"/confirm/#{encoded_token}")
      |> assert_path(~p"/confirm/#{encoded_token}")
      |> assert_has("p",
        with:
          "It looks like your confirmation link has expired. A new link has been sent to your email."
      )

      platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

      assert_email_sent(fn email ->
        assert email.subject == "#{platform_name}: Confirm your account"
        assert to_string(email.text_body) =~ "Please use the link below to confirm your account:"
        assert email.html_body =~ "Please click the button below to confirm your account:"
      end)
    end
  end

  describe "invite" do
    test "- accept an invite and log in the user", %{org: org, user: user} do
      {:ok, invite} =
        Accounts.invite(%{"email" => "joe@example.com", "role" => "view"}, org, user)

      platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

      build_conn()
      |> visit(~p"/invite/#{invite.token}")
      |> assert_has("h1", with: "You've been invited to join #{org.name} on #{platform_name}")
      |> fill_in("Name", with: "Sgt Pepper")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_path(~p"/orgs")
      |> assert_has("h1", with: "Welcome to NervesHub!")
      |> assert_has("div", with: org.name)

      assert_email_sent(fn email ->
        assert email.subject == "#{platform_name}: Sgt Pepper has been added to Jeff"

        assert to_string(email.text_body) =~
                 "*Sgt Pepper* has been added to the *Jeff* organization by Jeff."

        assert email.html_body =~
                 "<strong>Sgt Pepper</strong> has been added to the <strong>Jeff</strong> organization by <strong>Jeff</strong>."
      end)
    end
  end
end
