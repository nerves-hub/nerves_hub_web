defmodule NervesHubWWWWeb.UserSocket do
  use Phoenix.Socket

  channel("user_console", NervesHubWWWWeb.UserConsoleChannel)

  def connect(%{"token" => token}, socket) do
    case Phoenix.Token.verify(socket, "user salt", token, max_age: 86400) do
      {:ok, user_id} ->
        socket = assign(socket, :auth_user_id, user_id)
        {:ok, socket}

      {:error, _} ->
        :error
    end
  end

  def id(%{assigns: %{auth_user_id: user_id}}) do
    "user_socket:#{user_id}"
  end

  def id(_socket) do
    nil
  end
end
