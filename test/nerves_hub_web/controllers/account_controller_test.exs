defmodule NervesHubWeb.AccountControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Swoosh.TestAssertions

  alias NervesHub.Accounts

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
