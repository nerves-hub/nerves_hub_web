defmodule NervesHubWeb.EventStreamSocketTest do
  use NervesHubWeb.ChannelCase

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHub.Products.ApiKeys
  alias NervesHubWeb.EventStreamSocket
  alias Phoenix.Socket.Broadcast

  describe "connect/3" do
    test "connects with a valid token" do
      user = Fixtures.user_fixture()
      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(EventStreamSocket, %{"token" => user_token})

      assert socket.assigns.current_scope.user.id == user.id
    end

    test "connects with a product API key" do
      %{api_key: api_key, product: product, token: token} = key_fixture()

      {:ok, socket} = connect(EventStreamSocket, %{"token" => token})

      assert socket.assigns.current_scope.api_key.id == api_key.id
      assert socket.assigns.current_scope.product.id == product.id
      assert is_nil(socket.assigns.current_scope.user)
    end

    test "a socket opened with a key is disconnected when the key is deactivated" do
      %{api_key: api_key, product: product, token: token, user: user} = key_fixture()

      {:ok, socket} = connect(EventStreamSocket, %{"token" => token})

      socket_id = EventStreamSocket.id(socket)
      assert socket_id == ApiKeys.socket_id(api_key)

      # Phoenix disconnects every socket with this id on a "disconnect" broadcast.
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, socket_id)
      {:ok, _} = ApiKeys.deactivate(product, user, api_key.id)

      assert_receive %Broadcast{topic: ^socket_id, event: "disconnect"}
    end

    test "fails to connect with a deactivated product API key" do
      %{api_key: api_key, product: product, token: token, user: user} = key_fixture()
      {:ok, _} = ApiKeys.deactivate(product, user, api_key.id)

      {:error, :invalid_token} = connect(EventStreamSocket, %{"token" => token})
    end

    test "fails to connect with an invalid token" do
      {:error, :invalid_token} = connect(EventStreamSocket, %{"token" => "invalid-token"})
    end

    test "fails to connect without a token" do
      {:error, :no_token} = connect(EventStreamSocket, %{})
    end
  end

  defp key_fixture() do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    {:ok, api_key, token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => "view"})

    %{user: user, org: org, product: product, api_key: api_key, token: token}
  end
end
