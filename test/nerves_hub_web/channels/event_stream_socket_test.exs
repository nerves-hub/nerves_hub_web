defmodule NervesHubWeb.EventStreamSocketTest do
  use NervesHubWeb.ChannelCase

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHubWeb.EventStreamSocket

  describe "connect/3" do
    test "connects with a valid token" do
      user = Fixtures.user_fixture()
      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(EventStreamSocket, %{"token" => user_token})

      assert socket.assigns.user.id == user.id
    end

    test "fails to connect with an invalid token" do
      {:error, :invalid_token} = connect(EventStreamSocket, %{"token" => "invalid-token"})
    end

    test "fails to connect without a token" do
      {:error, :no_token} = connect(EventStreamSocket, %{})
    end
  end
end
