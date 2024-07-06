defmodule NervesHubWeb.AccountControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Swoosh.TestAssertions

  alias NervesHub.Accounts

  describe "new" do
    test "renders registration form when registrations are enabled" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      conn = get(build_conn(), ~p"/register")

      assert html_response(conn, 200) =~ "Create New Account"
    end

    test "redirects to /login with a flash when registrations are disabled" do
      Application.put_env(:nerves_hub, :open_for_registrations, false)

      conn = get(build_conn(), ~p"/register")

      assert redirected_to(conn, 302) =~ ~p"/login"
    end
  end

  describe "create" do
    test "registers new account" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      conn =
        post(build_conn(), ~p"/register", %{
          "user" => %{
            "name" => "My Name",
            "email" => "mrjosh@josh.com",
            "password" => "12345678"
          }
        })

      assert redirected_to(conn, 302) =~ "/"

      assert get_session(conn, :phoenix_flash) == %{
               "info" => "Account successfully created, login below"
             }

      platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

      assert_email_sent(subject: "Welcome to #{platform_name}!")
    end

    test "requires information new account" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      conn =
        post(build_conn(), ~p"/register", %{
          "user" => %{}
        })

      assert html_response(conn, 200) =~ "can&#39;t be blank"
    end
  end

  describe "invite" do
    test "renders invite creation form", %{org: org, user: user} do
      {:ok, invite} =
        Accounts.invite(%{"email" => "joe@example.com", "role" => "view"}, org, user)

      conn = get(build_conn(), ~p"/invite/#{invite.token}")

      assert html_response(conn, 200) =~
               "You will be added to the #{org.name} organization"
    end
  end

  describe "accept_invite" do
    test "accepts submitted invitation", %{user: user, org: org} do
      {:ok, invite} =
        Accounts.invite(%{"email" => "joe@example.com", "role" => "view"}, org, user)

      conn =
        post(build_conn(), ~p"/invite/#{invite.token}", %{
          "user" => %{
            "name" => "My Name",
            "email" => "not_joe@example.com",
            "password" => "12345678"
          }
        })

      assert redirected_to(conn, 302) =~ "/"

      assert get_session(conn, :phoenix_flash) == %{
               "info" => "Account successfully created, login below"
             }

      assert_email_sent(subject: "#{user.name} added My Name to #{org.name}")
    end
  end
end
