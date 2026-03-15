defmodule NervesHub.Ash.Accounts.UserTokenTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Accounts.UserToken
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    %{user: user}
  end

  describe "create_api_token" do
    test "creates an API token for user", %{user: user} do
      token = UserToken.create_api_token!(user.id, "test token")

      assert token.id
      assert token.user_id == user.id
      assert token.context == "api"
      assert token.note == "test token"
    end
  end

  describe "list_by_user" do
    test "returns API tokens for user", %{user: user} do
      UserToken.create_api_token!(user.id, "token 1")

      tokens = UserToken.list_by_user!(user.id)

      assert length(tokens) >= 1
      assert Enum.all?(tokens, &(&1.user_id == user.id))
    end
  end

  describe "mark_last_used" do
    test "updates last_used timestamp", %{user: user} do
      token = UserToken.create_api_token!(user.id, "mark test")

      assert token.last_used == nil
      updated = UserToken.mark_last_used!(token)
      assert updated.last_used != nil
    end
  end

  describe "destroy" do
    test "deletes token", %{user: user} do
      token = UserToken.create_api_token!(user.id, "delete test")

      assert :ok = UserToken.destroy!(token)
    end
  end
end
