defmodule NervesHubWeb.Helpers.AuthorizedLiveView do
  alias NervesHub.Accounts.OrgUser
  alias NervesHubWeb.Helpers.Authorization
  alias NervesHubWeb.Mounts.RequireAuthzOnEvent
  import Phoenix.LiveView

  defmacro __using__(_) do
    quote do
      import NervesHubWeb.Helpers.AuthorizedLiveView

      on_mount(RequireAuthzOnEvent)
      on_mount(Sentry.LiveViewHook)

      @impl Phoenix.LiveView
      def mount(params, session, %{private: %{wrapped_in_authorization?: false}} = socket) do
        case mount(params, session, RequireAuthzOnEvent.wrap(socket)) do
          {:ok, %{private: %{authorization_applied?: true, authorization_granted?: true}} = socket} ->
            {:ok, socket}

          {:ok, %{private: %{authorization_applied?: true, authorization_granted?: true}} = socket, options} ->
            {:ok, socket, options}

          {:ok, %{private: %{authorization_applied?: true, authorization_granted?: false}} = socket} ->
            raise RequireAuthzOnEvent.AuthorizationFailed, message: "Authorization failed in `mount/3` on #{__MODULE__}.\n\nAnnotation: #{inspect(socket.private.authorization_info)}"

          {:ok, %{private: %{authorization_applied?: true, authorization_granted?: false}} = socket, _options} ->
            raise RequireAuthzOnEvent.AuthorizationFailed, message: "Authorization failed in `mount/3` on #{__MODULE__}.\n\nAnnotation: #{inspect(socket.private.authorization_info)}"

          other ->
            raise RequireAuthzOnEvent.AuthorizationNotApplied,
              message:
                "No authorization applied in `mount/3` on #{__MODULE__}.\n\nUse authorize/3, authorization_not_needed/1 or confirm_user_is_authorized/1 on the socket."
        end
      end

      @impl Phoenix.LiveView
      def handle_event(event, params, %{private: %{wrapped_in_authorization?: false}} = socket) do
        case handle_event(event, params, RequireAuthzOnEvent.wrap(socket)) do
          {:noreply, %{private: %{authorization_applied?: true, authorization_granted?: true}} = socket} ->
            {:noreply, socket}

          {:reply, reply, %{private: %{authorization_applied?: true, authorization_granted?: true}} = socket} ->
            {:reply, reply, socket}

          {:noreply, %{private: %{authorization_applied?: true, authorization_granted?: false}} = socket} ->
            raise RequireAuthzOnEvent.AuthorizationFailed,
              message: "Authorization failed in `handle_event/3` for event \"#{event}\" on #{__MODULE__}.\n\nAnnotation: #{inspect(socket.private.authorization_info)}"

          {:reply, _reply, %{private: %{authorization_applied?: true, authorization_granted?: false}} = socket} ->
            raise RequireAuthzOnEvent.AuthorizationFailed,
              message: "Authorization failed in `handle_event/3` for event \"#{event}\" on #{__MODULE__}.\n\nAnnotation: #{inspect(socket.private.authorization_info)}"

          _other ->
            raise RequireAuthzOnEvent.AuthorizationNotApplied,
              message:
                "No authorization applied in `handle_event/3` for event \"#{event}\" on #{__MODULE__}.\n\nUse authorize/3, authorization_not_needed/1 or confirm_user_is_authorized/1 on the socket."
        end
      end

    end
  end

  def authorize!(%{assigns: %{org_user: org_user}} = socket, permission) do
    if Authorization.authorized?(permission, org_user) do
      socket
      |> put_private(:authorization_granted?, true)
      |> annotate_authorization(permission, org_user)
    else
      raise RequireAuthzOnEvent.AuthorizationFailed,
        message: "Authorization failed in #{__MODULE__}.\n\nAuthorization false for:\nRole:#{org_user.role}\nPermission: #{permission}"
    end
  end

  def authorize!(socket, permission, org_user) do
    if Authorization.authorized?(permission, org_user) do
      socket
      |> put_private(:authorization_granted?, true)
      |> annotate_authorization(permission, org_user)
    else
      raise RequireAuthzOnEvent.AuthorizationFailed,
        message: "Authorization failed in #{__MODULE__}.\n\nAuthorization false for:\nRole:#{org_user.role}\nPermission: #{permission}"
    end
  end

  @doc """
  #This function explicitly marks an event as not needing authorization. Which just marks it as authorized.
  """
  def authorization_not_needed(socket), do: socket |> confirm_user_is_authorized(:not_needed)

  @doc """
  This function explicitly marks an event as authorized.
  """
  def confirm_user_is_authorized(socket, annotation),
    do: socket |> put_private(:authorization_granted?, true) |> annotate_authorization(annotation)

  defp annotate_authorization(socket, annotation),
    do: socket |> put_private(:authorization_applied?, true) |> put_private(:authorization_info, annotation)

  defp annotate_authorization(socket, permission, %OrgUser{} = org_user),
    do:
      socket
      |> put_private(:authorization_applied?, true)
      |> put_private(:authorization_info, "Permission: #{permission}, Role: #{org_user.role}")

end
