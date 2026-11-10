defmodule NervesHubWeb.Mounts.RequireAuthorization do
  import Phoenix.LiveView, only: [put_private: 3]

  alias NervesHub.Accounts.Scope
  alias NervesHubWeb.Access.Authorization
  alias Phoenix.LiveView.Socket

  defmodule AuthorizationNotApplied do
    defexception [:message]
  end

  defmodule AuthorizationFailed do
    defexception [:message]
  end

  def on_mount(_, _assigns, _session, socket) do
    {:cont, reset(socket)}
  end

  @doc """
  Clears the authorization state and marks the socket as inside the checking
  wrapper. Every wrapped callback starts here, so nothing a previous callback
  was granted carries over.
  """
  @spec wrap(Socket.t()) :: Socket.t()
  def wrap(socket), do: socket |> reset() |> put_private(:wrapped_in_authorization?, true)

  @doc """
  Marks the socket as outside the wrapper again, so the next callback goes
  through the check. What was granted stays readable until then.
  """
  @spec unwrap(Socket.t()) :: Socket.t()
  def unwrap(socket), do: put_private(socket, :wrapped_in_authorization?, false)

  defp reset(socket) do
    socket
    |> put_private(:wrapped_in_authorization?, false)
    |> put_private(:authorization_applied?, false)
    |> put_private(:authorization_granted?, false)
    |> put_private(:authorization_info, nil)
  end

  @spec authorize!(Socket.t(), atom(), struct() | [non_neg_integer()]) :: Socket.t()
  def authorize!(socket, permission, subject) do
    %{assigns: %{current_scope: scope}} = socket

    if Authorization.authorized?(permission, scope, subject) do
      socket
      |> put_private(:authorization_granted?, true)
      |> annotate_authorization(permission, scope)
    else
      raise AuthorizationFailed,
        message:
          "Authorization failed in #{__MODULE__}.\n\nAuthorization false for:\nRole: #{scope.role}\nPermission: #{permission}"
    end
  end

  @spec authorization_not_needed(Socket.t()) :: Socket.t()
  def authorization_not_needed(socket), do: confirm_user_is_authorized(socket, :not_needed)

  @spec confirm_user_is_authorized(Socket.t(), term()) :: Socket.t()
  def confirm_user_is_authorized(socket, annotation),
    do: socket |> put_private(:authorization_granted?, true) |> annotate_authorization(annotation)

  defp annotate_authorization(socket, annotation),
    do: socket |> put_private(:authorization_applied?, true) |> put_private(:authorization_info, annotation)

  defp annotate_authorization(socket, permission, %Scope{} = scope),
    do:
      socket
      |> put_private(:authorization_applied?, true)
      |> put_private(:authorization_info, "Permission: #{permission}, Role: #{scope.role}")
end
