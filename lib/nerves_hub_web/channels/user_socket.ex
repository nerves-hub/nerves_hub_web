defmodule NervesHubWeb.UserSocket do
  @moduledoc """
  The dashboard's socket for device consoles and local shells.

  It signs in with the browser's session cookie, as the LiveView socket does,
  so it works only while that session does. The page sends its CSRF token when
  it connects, which stops another site opening the socket with the user's
  cookie.

  Its id is the session's `live_socket_id`, the one the LiveView socket uses
  too, so logging out disconnects both. Consoles opened with an API token go
  through `NervesHubWeb.APISocket` instead.
  """
  use Phoenix.Socket

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User

  channel("user:console:*", NervesHubWeb.UserConsoleChannel)
  channel("user:local_shell:*", NervesHubWeb.UserLocalShellChannel)

  @impl Phoenix.Socket
  def connect(_params, socket, %{session: %{"user_token" => token, "live_socket_id" => live_socket_id}})
      when is_binary(token) do
    case Accounts.get_user_by_session_token(token) do
      %User{} = user ->
        {:ok, socket |> assign(:user, user) |> assign(:live_socket_id, live_socket_id)}

      nil ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl Phoenix.Socket
  def id(%{assigns: %{live_socket_id: live_socket_id}}), do: live_socket_id
  def id(_socket), do: nil
end
