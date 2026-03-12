defmodule NervesHubWeb.Mounts.RequireAuthorization do
  import Phoenix.LiveView

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
    socket =
      socket
      |> put_private(:wrapped_in_authorization?, false)
      |> put_private(:authorization_applied?, false)
      |> put_private(:authorization_granted?, false)
      |> attach_hook(:require_authorization, :handle_event, &event/3)

    # handle_params hooks can only be attached to router-mounted views.
    socket =
      try do
        attach_hook(socket, :require_authorization, :handle_params, &params/3)
      rescue
        RuntimeError -> socket
      end

    {:cont, socket}
  end

  defp event(_, _, socket) do
    socket =
      socket
      |> put_private(:wrapped_in_authorization?, false)
      |> put_private(:authorization_applied?, false)
      |> put_private(:authorization_granted?, false)

    {:cont, socket}
  end

  defp params(_, _, socket) do
    socket =
      socket
      |> put_private(:wrapped_in_authorization?, false)
      |> put_private(:authorization_applied?, false)
      |> put_private(:authorization_granted?, false)

    {:cont, socket}
  end

  @spec wrap(Socket.t()) :: Socket.t()
  def wrap(socket), do: put_private(socket, :wrapped_in_authorization?, true)

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
