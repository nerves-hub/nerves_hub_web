defmodule NervesHubWeb.AccountControllerTest do
  use NervesHubWeb.ConnCase.Browser

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User

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
      {:ok, invite} =
        Accounts.invite(
          %{
            "name" => "Joe",
            "email" => "joe@example.com"
          },
          conn.assigns.tenant
        )

      conn = get(conn, account_path(conn, :invite, invite.token))

      assert html_response(conn, 200) =~
               "You will be added to the #{conn.assigns.tenant.name} tenant"
    end
  end

  describe "accept_invite" do
    test "accepts submitted invitation", %{
      conn: conn
    } do
      {:ok, invite} =
        Accounts.invite(
          %{
            "name" => "Joe",
            "email" => "joe@example.com"
          },
          conn.assigns.tenant
        )

      conn =
        put(
          conn,
          account_path(conn, :accept_invite, invite.token, %{
            "user" => %{
              "name" => "My Name",
              "email" => "joe@example.com",
              "password" => "12345678"
            }
          })
        )

      assert redirected_to(conn, 302) =~ "/"

      assert get_session(conn, :phoenix_flash) == %{
               "info" => "Account successfully created, login below"
             }
    end
  end

  describe "edit" do
    test "renders account edit form", %{
      conn: conn
    } do
      conn = get(conn, account_path(conn, :edit))
      assert html_response(conn, 200) =~ "Edit Account"
    end
  end

  describe "update" do
    test "can update an account", %{
      conn: conn
    } do
      conn =
        conn
        |> Map.merge(%{assigns: %{user: %User{name: "frodo"}}})
        |> put(
          account_path(conn, :update, %{
            "user" => %{
              "name" => "My Newest Name"
            }
          })
        )

      assert html_response(conn, 302) =~ account_path(conn, :edit)
    end
  end

  describe "create" do
    test "creates a user and tenant", %{
      conn: conn
    } do
      conn =
        post(
          conn,
          account_path(conn, :create, %{
            "user" => %{
              "name" => "My Name",
              "tenant_name" => "a Tenant",
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
              "name" => "My Name",
              "tenant_name" => "a Tenant",
              "email" => "joe@example.com",
              "password" => "12345"
            }
          })
        )

      assert html_response(conn, 200) =~ "should be at least 8 character"
    end
  end
end
