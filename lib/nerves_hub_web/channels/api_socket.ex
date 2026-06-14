defmodule NervesHubWeb.APISocket do
  @moduledoc """
  Authentication using API tokens has been encapsulated in this socket as
  it will allow us to add *future* restrictions around how many concurrent
  websocket connections a user can have open at one time.
  """
  use Phoenix.Socket

  alias NervesHub.Accounts

  channel("user:console:*", NervesHubWeb.UserConsoleChannel)
  channel("user:local_shell:*", NervesHubWeb.UserLocalShellChannel)

  def connect(%{"token" => token}, socket) do
    with {:ok, user, user_token} <- Accounts.fetch_user_by_api_token(token),
         :ok <- Accounts.mark_last_used(user_token) do
      {:ok, assign(socket, :user, user)}
    else
      _ -> :error
    end
  end

  def connect(_, _socket) do
    :error
  end

  def id(%{assigns: %{user: user}}) do
    "api_socket:#{user.id}"
  end

  def id(_socket) do
    nil
  end
end
