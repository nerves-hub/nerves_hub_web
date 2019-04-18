defmodule NervesHubWWWWeb.AccountControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Accounts

  describe "new" do
    test "renders account creation form", %{
      conn: conn
    } do
      conn = get(conn, account_path(conn, :new))
      assert html_response(conn, 200) =~ "Create an Account"
    end
  end

  describe "invite" do
    test "renders invite creation form", %{
      conn: conn
    } do
      {:ok, invite} = Accounts.invite(%{"email" => "joe@example.com"}, conn.assigns.current_org)

      conn = get(conn, account_path(conn, :invite, invite.token))

      assert html_response(conn, 200) =~
               "You will be added to the #{conn.assigns.current_org.name} org"
    end
  end

  describe "accept_invite" do
    test "accepts submitted invitation", %{
      conn: conn
    } do
      {:ok, invite} = Accounts.invite(%{"email" => "joe@example.com"}, conn.assigns.current_org)

      conn =
        post(
          conn,
          account_path(conn, :accept_invite, invite.token, %{
            "user" => %{
              "username" => "MyName",
              "email" => "not_joe@example.com",
              "password" => "12345678"
            }
          })
        )

      assert redirected_to(conn, 302) =~ "/"

      assert get_session(conn, :phoenix_flash) == %{
               "info" => "Account successfully created, login below"
             }

      assert {:ok, %Accounts.User{username: "MyName"}} =
               Accounts.get_user_by_email("joe@example.com")
    end
  end

  describe "edit" do
    test "renders account edit form", %{
      conn: conn
    } do
      conn = get(conn, account_path(conn, :edit))
      assert html_response(conn, 200) =~ "Organization settings"
      assert html_response(conn, 200) =~ account_certificate_path(conn, :index)
      assert html_response(conn, 200) =~ "type=\"password\""
    end
  end

  describe "update" do
    test "can update an account", %{
      conn: conn,
      current_user: user
    } do
      conn =
        conn
        |> put(
          account_path(conn, :update, %{
            "user" => %{
              "username" => "MyNewestName",
              "password" => "foobarbaz",
              "current_password" => user.password
            }
          })
        )

      assert html_response(conn, 302) =~ account_path(conn, :edit)

      updated_user = Accounts.get_user(user.id) |> elem(1)

      refute updated_user.password_hash == user.password_hash
    end

    test "fails with missing password", %{
      conn: conn
    } do
      conn =
        conn
        |> put(
          account_path(conn, :update, %{
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
      conn: conn
    } do
      conn =
        conn
        |> put(
          account_path(conn, :update, %{
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

  describe "create" do
    test "creates a user and org", %{
      conn: conn
    } do
      conn =
        post(
          conn,
          account_path(conn, :create, %{
            "user" => %{
              "username" => "MyName",
              "email" => "joe@example.com",
              "password" => "12345678"
            }
          })
        )

      assert redirected_to(conn, 302) =~ "/"
    end

    test "requires an 8 character password", %{
      conn: conn
    } do
      conn =
        post(
          conn,
          account_path(conn, :create, %{
            "user" => %{
              "username" => "MyName",
              "org_name" => "a Org",
              "email" => "joe@example.com",
              "password" => "12345"
            }
          })
        )

      assert html_response(conn, 200) =~ "should be at least 8 character"
    end
  end
end
