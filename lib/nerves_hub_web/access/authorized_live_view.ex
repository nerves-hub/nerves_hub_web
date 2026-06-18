defmodule NervesHubWeb.Access.AuthorizedLiveView do
  import Phoenix.LiveView

  alias NervesHubWeb.Mounts.RequireAuthorization

  require Logger

  defmacro __using__(_) do
    quote do
      use NervesHubWeb.Access.AuthDecorator

      import NervesHubWeb.Access.AuthorizedLiveView
      import NervesHubWeb.Mounts.RequireAuthorization

      # The authorization wrapper macro handles all possible LiveView callback
      # return types ({:ok, socket}, {:ok, socket, opts}, {:reply, reply, socket})
      # but individual modules typically only use a subset, causing dialyzer
      # pattern_match warnings.
      @dialyzer [:no_match]

      on_mount(RequireAuthorization)

      @impl Phoenix.LiveView
      def mount(params, session, %{private: %{wrapped_in_authorization?: false}} = socket) do
        case mount(params, session, RequireAuthorization.wrap(socket)) do
          {:ok, socket} ->
            case check_socket_authorized(socket) do
              {:ok, socket} ->
                {:ok, socket}

              {:error, RequireAuthorization.AuthorizationFailed = e} ->
                raise e,
                  message:
                    "Authorization failed in `mount/3` on #{__MODULE__}.\n\nAnnotation: #{inspect(socket.private.authorization_info)}"

              {:error, RequireAuthorization.AuthorizationNotApplied = e} ->
                raise e,
                  message:
                    "No authorization applied in `mount/3` on #{__MODULE__}.\n\nUse `@decorate` and `requires_permission/1`, `requires_no_permission/0` or `special_permission/1` to ensure authorization or use the functions in `RequireAuthorization` on the socket."
            end

          {:ok, socket, options} ->
            case check_socket_authorized(socket) do
              {:ok, socket} ->
                {:ok, socket, options}

              {:error, RequireAuthorization.AuthorizationFailed = e} ->
                raise e,
                  message:
                    "Authorization failed in `mount/3` on #{__MODULE__}.\n\nAnnotation: #{inspect(socket.private.authorization_info)}"

              {:error, RequireAuthorization.AuthorizationNotApplied = e} ->
                raise e,
                  message:
                    "No authorization applied in `mount/3` on #{__MODULE__}.\n\nUse `@decorate` and `requires_permission/1`, `requires_no_permission/0` or `special_permission/1` to ensure authorization or use the functions in `RequireAuthorization` on the socket."
            end
        end
      rescue
        e ->
          socket = handle_auth_failure(socket, e)
          {:ok, socket}
      end

      @impl Phoenix.LiveView
      def handle_params(unsigned_params, uri, %{private: %{wrapped_in_authorization?: false}} = socket) do
        {:noreply, socket} =
          try do
            handle_params(unsigned_params, uri, RequireAuthorization.wrap(socket))
          rescue
            e ->
              case e do
                %FunctionClauseError{module: __MODULE__, function: :handle_params, arity: 3} ->
                  {:noreply, RequireAuthorization.authorization_not_needed(socket)}

                e ->
                  reraise e, __STACKTRACE__
              end
          end

        case check_socket_authorized(socket) do
          {:ok, socket} ->
            {:noreply, socket}

          {:error, RequireAuthorization.AuthorizationFailed = e} ->
            raise e,
              message:
                "Authorization failed in `handle_params/3` on #{__MODULE__}.\n\nAnnotation: #{inspect(socket.private.authorization_info)}"

          {:error, RequireAuthorization.AuthorizationNotApplied = e} ->
            raise e,
              message:
                "No authorization applied in `handle_params/3` on #{__MODULE__}.\n\nUse `@decorate` and `requires_permission/1`, `requires_no_permission/0` or `special_permission/1` to ensure authorization or use the functions in `RequireAuthorization` on the socket."
        end
      rescue
        e ->
          socket = handle_auth_failure(socket, e)
          {:noreply, socket}
      end

      @impl Phoenix.LiveView
      def handle_event(event, params, %{private: %{wrapped_in_authorization?: false}} = socket) do
        case handle_event(event, params, RequireAuthorization.wrap(socket)) do
          {:noreply, socket} ->
            case check_socket_authorized(socket) do
              {:ok, socket} ->
                {:noreply, socket}

              {:error, RequireAuthorization.AuthorizationFailed = e} ->
                raise e,
                  message:
                    "Authorization failed in `handle_event/3` on #{__MODULE__}.\n\nAnnotation: #{inspect(socket.private.authorization_info)}"

              {:error, RequireAuthorization.AuthorizationNotApplied = e} ->
                raise e,
                  message:
                    "No authorization applied in `handle_event/3` on #{__MODULE__}.\n\nUse `@decorate` and `requires_permission/1`, `requires_no_permission/0` or `special_permission/1` to ensure authorization or use the functions in `RequireAuthorization` on the socket."
            end

          {:reply, reply, socket} ->
            case check_socket_authorized(socket) do
              {:ok, socket} ->
                {:reply, reply, socket}

              {:error, RequireAuthorization.AuthorizationFailed = e} ->
                raise e,
                  message:
                    "Authorization failed in `handle_event/3` for event \"#{event}\" on #{__MODULE__}.\n\nAnnotation: #{inspect(socket.private.authorization_info)}"

              {:error, RequireAuthorization.AuthorizationNotApplied = e} ->
                raise e,
                  message:
                    "No authorization applied in `handle_event/3` for event \"#{event}\" on #{__MODULE__}.\n\nUse `@decorate` and `requires_permission/1`, `requires_no_permission/0` or `special_permission/1` to ensure authorization or use the functions in `RequireAuthorization` on the socket."
            end
        end
      rescue
        e ->
          socket = handle_auth_failure(socket, e)
          {:noreply, socket}
      end
    end
  end

  def check_socket_authorized(socket) do
    case socket do
      %{private: %{authorization_applied?: true, authorization_granted?: true}} ->
        {:ok, socket}

      %{private: %{authorization_applied?: true, authorization_granted?: false}} ->
        {:error, RequireAuthorization.AuthorizationFailed}

      _other ->
        {:error, RequireAuthorization.AuthorizationNotApplied}
    end
  end

  # AuthorizationNotApplied means a developer forgot to annotate a callback - always re-raise
  def handle_auth_failure(_, %RequireAuthorization.AuthorizationNotApplied{} = e) do
    raise e
  end

  if Mix.env() == :test do
    # In test mode, re-raise AuthorizationFailed when flash is not available (unit tests).
    # Integration tests (via live/2) have flash initialized and get the flash message instead.
    def handle_auth_failure(%{assigns: assigns} = socket, %RequireAuthorization.AuthorizationFailed{} = e) do
      if Map.has_key?(assigns, :flash) do
        socket
        |> put_flash(:error, "Sorry. You were denied access. Please check your role or contact your support.")
      else
        raise e
      end
    end
  end

  def handle_auth_failure(socket, e) do
    Logger.error("Auth failure caught: #{inspect(e)}")

    socket
    |> put_flash(:error, "Sorry. You were denied access. Please check your role or contact your support.")
  end
end
