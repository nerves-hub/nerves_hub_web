defmodule NervesHubWeb.UserSocketTest do
  use NervesHubWeb.ChannelCase

  alias NervesHub.Fixtures
  alias NervesHubWeb.Auth
  alias NervesHubWeb.UserSocket
  alias Phoenix.Socket.Broadcast

  setup do
    user = Fixtures.user_fixture()

    # Signed in the way the dashboard signs people in, so the session the
    # socket reads has the same shape as a real one.
    session =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Auth.log_in_user(user)
      |> Plug.Conn.get_session()

    %{user: user, session: session}
  end

  test "connects as the session's user", %{user: user, session: session} do
    assert {:ok, socket} = connect(UserSocket, %{}, connect_info: %{session: session})
    assert socket.assigns.user.id == user.id
  end

  test "logging out disconnects the socket and stops it connecting again", %{session: session} do
    {:ok, socket} = connect(UserSocket, %{}, connect_info: %{session: session})

    # The id is the topic a socket listens on for "disconnect".
    socket_id = UserSocket.id(socket)
    :ok = NervesHubWeb.Endpoint.subscribe(socket_id)

    _ =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(session)
      |> Auth.log_out_user()

    assert_receive %Broadcast{topic: ^socket_id, event: "disconnect"}
    assert :error = connect(UserSocket, %{}, connect_info: %{session: session})
  end

  test "refuses a connection without a session", %{user: user} do
    # What the page used to send: a token for the user, valid for a day
    # whatever happened to the session it came from.
    token = Phoenix.Token.sign(NervesHubWeb.Endpoint, "user salt", user.id)

    assert :error = connect(UserSocket, %{"token" => token})
  end
end
