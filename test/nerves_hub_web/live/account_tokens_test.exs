defmodule NervesHubWeb.Live.AccountTokensTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts

  describe "list" do
    test "shows empty list if no tokens", %{conn: conn} do
      conn
      |> visit("/account/tokens")
      |> assert_has("h1", text: "User Access Tokens")
      |> refute_has("#user_tokens > tr.item")
    end

    test "lists user tokens", %{conn: conn, user: user} do
      {:ok, token} = Accounts.create_user_token(user, "The Josh Token")

      conn
      |> visit("/account/tokens")
      |> assert_has("h1", text: "User Access Tokens")
      |> assert_has("tr.item > td", text: token.note)
    end

    test "delete token", %{conn: conn, user: user} do
      {:ok, token} = Accounts.create_user_token(user, "The Josh Token")

      conn
      |> visit("/account/tokens")
      |> assert_has("h1", text: "User Access Tokens")
      |> assert_has("tr.item > td", text: token.note)
      |> click_link("Delete")
      |> refute_has("tr.item > td ", text: token.note)
      |> assert_has("div", text: "Token deleted")
    end
  end

  describe "new" do
    test "requires token note", %{conn: conn, user: user} do
      conn =
        conn
        |> visit("/account/tokens/new")
        |> assert_has("h1", text: "New User Access Token")
        |> fill_in("Note", with: "An amazing token")
        |> click_button("Generate")
        |> assert_path("/account/tokens")
        |> assert_has("tr.item > td", text: "An amazing token")

      [token] = Accounts.get_user_tokens(user)

      assert_has(conn, "div", text: "Token created : #{token.token}")
    end

    test "token note can't be blank", %{conn: conn} do
      conn
      |> visit("/account/tokens/new")
      |> assert_has("h1", text: "New User Access Token")
      |> click_button("Generate")
      |> assert_path("/account/tokens/new")
      |> assert_has("div", text: "There was an issue creating the token")
      |> assert_has(".help-block", text: "can't be blank")
    end

    test "token note will be trimmed", %{conn: conn} do
      conn
      |> visit("/account/tokens/new")
      |> assert_has("h1", text: "New User Access Token")
      |> fill_in("Note", with: "    An    amazing    token    ")
      |> click_button("Generate")
      |> assert_path("/account/tokens")
      |> assert_has("tr.item > td", text: "An amazing token")
    end
  end
end
