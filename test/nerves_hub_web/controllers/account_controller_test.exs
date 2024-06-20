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
            "username" => "MyName",
            "email" => "not_joe@example.com",
            "password" => "12345678"
          }
        })

      assert redirected_to(conn, 302) =~ "/"

      assert get_session(conn, :phoenix_flash) == %{
               "info" => "Account successfully created, login below"
             }

      assert_email_sent(subject: "User #{user.username} added MyName to #{org.name}")
    end
  end

  describe "edit" do
    test "renders account edit form", %{
      conn: conn,
      user: user
    } do
      conn = get(conn, Routes.account_path(conn, :edit, user.username))
      assert html_response(conn, 200) =~ "Personal Info"

      assert html_response(conn, 200) =~ "type=\"password\""
    end
  end

  describe "update" do
    test "can update an account", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> put(
          Routes.account_path(conn, :update, user.username, %{
            "user" => %{
              "username" => "MyNewestName",
              "password" => "foobarbaz",
              "current_password" => user.password
            }
          })
        )

      assert html_response(conn, 302) =~ Routes.account_path(conn, :edit, "MyNewestName")

      updated_user = Accounts.get_user(user.id) |> elem(1)

      refute updated_user.password_hash == user.password_hash
    end

    test "fails with missing password", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> put(
          Routes.account_path(conn, :update, user.username, %{
            "user" => %{
              "username" => "MyNewestName",
              "password" => "12345678",
              "current_password" => ""
            }
          })
        )

      assert html_response(conn, 200) =~ "Current password is incorrect."
    end

    test "fails with incorrect password", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> put(
          Routes.account_path(conn, :update, user.username, %{
            "user" => %{
              "username" => "MyNewestName",
              "password" => "12345678",
              "current_password" => "not the current password"
            }
          })
        )

      assert html_response(conn, 200) =~ "Current password is incorrect."
    end
  end
end
