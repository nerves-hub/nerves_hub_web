defmodule NervesHubWeb.Live.AccountTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts

  describe "update" do
    test "can update username", %{conn: conn, user: user} do
      conn
      |> visit("/account")
      |> assert_has("h1", text: "Personal Info")
      |> fill_in("Name", with: "My Newest Name")
      |> click_button("Save Changes")
      |> assert_path("/account")
      |> assert_has("div", text: "Account updated")

      updated_user = Accounts.get_user(user.id) |> elem(1)

      assert updated_user.name == "My Newest Name"
    end

    test "can update password", %{conn: conn, user: user} do
      conn
      |> visit("/account")
      |> assert_has("h1", text: "Personal Info")
      |> fill_in("Old Password", with: user.password)
      |> fill_in("New Password", with: "foobarbaz")
      |> click_button("Save Changes")
      |> assert_path("/account")
      |> assert_has("div", text: "Account updated")

      updated_user = Accounts.get_user(user.id) |> elem(1)

      refute updated_user.password_hash == user.password_hash
    end

    test "fails with missing password", %{conn: conn} do
      conn
      |> visit("/account")
      |> assert_has("h1", text: "Personal Info")
      |> fill_in("New Password", with: "12345678")
      |> click_button("Save Changes")
      |> assert_path("/account")
      |> assert_has("div",
        text: "You must provide a current password in order to change your email or password."
      )
    end

    test "fails with incorrect password", %{conn: conn} do
      conn
      |> visit("/account")
      |> assert_has("h1", text: "Personal Info")
      |> fill_in("Old Password", with: "not the current password")
      |> fill_in("New Password", with: "12345678")
      |> click_button("Save Changes")
      |> assert_path("/account")
      |> assert_has("div", text: "Current password is incorrect.")
    end
  end

  describe "delete" do
    test "requires the user to confirm their username", %{conn: conn, user: user} do
      conn
      |> visit("/account/delete")
      |> assert_has("h1", text: "Are you absolutely sure?")
      |> click_button("I understand the consequences, delete this account")
      |> assert_path("/account/delete")
      |> assert_has("div", text: "Please type #{user.email} to confirm.")
    end

    test "requires the user to confirm their username (it has to be correct)", %{
      conn: conn,
      user: user
    } do
      conn
      |> visit("/account/delete")
      |> assert_has("h1", text: "Are you absolutely sure?")
      |> fill_in("Please type #{user.email} to confirm.", with: "#{user.email}-nah")
      |> click_button("I understand the consequences, delete this account")
      |> assert_path("/account/delete")
      |> assert_has("div", text: "Please type #{user.email} to confirm.")
    end

    test "deletes your account", %{conn: conn, user: user} do
      conn
      |> visit("/account/delete")
      |> assert_has("h1", text: "Are you absolutely sure?")
      |> fill_in("Please type #{user.email} to confirm.", with: user.email)
      |> click_button("I understand the consequences, delete this account")
      |> assert_path("/login")
      |> assert_has("div", text: "Your account has successfully been deleted")
    end
  end
end
