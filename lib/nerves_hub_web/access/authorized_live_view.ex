defmodule NervesHubWeb.Access.AuthorizedLiveView do
  @moduledoc """
  Makes a LiveView refuse to finish `mount/3`, `handle_params/3` or
  `handle_event/3` unless the callback stated what authorization it needs.

  Each callback is wrapped. The wrapper clears the authorization state on the
  socket, runs the real callback and then checks that the callback either
  authorized the user (`@decorate requires_permission/1`, or `authorize!/3` in
  the body) or declared that there is nothing to authorize
  (`@decorate requires_no_permission/0`, `@decorate special_permission/1`).

    * A clause that states nothing does not compile, see
      `NervesHubWeb.Access.AuthorizationDeclared`.
    * A callback that said it would authorize in its body
      (`@decorate authorizes_in_body()`) and then did not raises
      `AuthorizationNotApplied`. This is a programming error and is never
      rescued. Note that the body has already run by then, which is why the
      decorators that check before the body are preferred.
    * A callback that is refused (`AuthorizationFailed`, or the older
      `NervesHubWeb.UnauthorizedError`) is turned into a flash message.
      Events keep the socket as it was before the event. `mount/3` and
      `handle_params/3` have nothing sensible to render, so they redirect.

  Any other exception passes through untouched.

  Events that never reach the LiveView's `handle_event/3` are checked the same
  way where they are handled: LiveComponents by
  `NervesHubWeb.Access.AuthorizedLiveComponent` and the device page tabs, whose
  hooks halt the event, by `NervesHubWeb.Access.AuthorizedTab`.

  An upload's `progress:` function is driven by the client too. In all three
  it has to be `authorized_progress(&handle_progress/3)`, and the clauses of
  `handle_progress/3` need a decorator like any event.
  """

  import Phoenix.LiveView

  alias NervesHubWeb.Mounts.RequireAuthorization
  alias NervesHubWeb.Mounts.RequireAuthorization.AuthorizationFailed
  alias NervesHubWeb.Mounts.RequireAuthorization.AuthorizationNotApplied

  require Logger

  @denied_message "Sorry. You were denied access. Please check your role or contact your support."

  defmacro __using__(_) do
    quote do
      use NervesHubWeb.Access.AuthorizationDeclared, mount: 3, handle_params: 3, handle_event: 3, handle_progress: 3

      import NervesHubWeb.Access.AuthorizedLiveView
      import NervesHubWeb.Mounts.RequireAuthorization

      alias NervesHubWeb.Access.AuthorizedLiveView
      # The decorators handle every callback return shape, but any one module
      # only uses a few of them, which dialyzer reports as pattern_match
      # warnings.
      @dialyzer [:no_match]

      on_mount(RequireAuthorization)

      @impl Phoenix.LiveView
      def mount(params, session, %{private: private} = socket) when not is_wrapped(private) do
        params
        |> mount(session, RequireAuthorization.wrap(socket))
        |> AuthorizedLiveView.enforce!(__MODULE__, "mount/3")
      rescue
        e in [AuthorizationFailed, NervesHubWeb.UnauthorizedError] ->
          {:ok, AuthorizedLiveView.deny_navigation(socket, e, __MODULE__, "mount/3")}
      end

      @impl Phoenix.LiveView
      def handle_params(unsigned_params, uri, %{private: private} = socket) when not is_wrapped(private) do
        wrapped = RequireAuthorization.wrap(socket)

        result =
          try do
            handle_params(unsigned_params, uri, wrapped)
          rescue
            # The LiveView has no handle_params/3 of its own that takes this.
            # mount/3 has already been checked and there is nothing more to do.
            e in FunctionClauseError ->
              if AuthorizedLiveView.no_clause_for?(e, __MODULE__, :handle_params, 3, __STACKTRACE__) do
                {:noreply, RequireAuthorization.authorization_not_needed(wrapped)}
              else
                reraise e, __STACKTRACE__
              end
          end

        AuthorizedLiveView.enforce!(result, __MODULE__, "handle_params/3")
      rescue
        e in [AuthorizationFailed, NervesHubWeb.UnauthorizedError] ->
          {:noreply, AuthorizedLiveView.deny_navigation(socket, e, __MODULE__, "handle_params/3")}
      end

      @impl Phoenix.LiveView
      def handle_event(event, params, %{private: private} = socket) when not is_wrapped(private) do
        event
        |> handle_event(params, RequireAuthorization.wrap(socket))
        |> AuthorizedLiveView.enforce!(__MODULE__, "handle_event/3 for event #{inspect(event)}")
      rescue
        e in [AuthorizationFailed, NervesHubWeb.UnauthorizedError] ->
          {:noreply, AuthorizedLiveView.deny(socket, e, __MODULE__, "handle_event/3 for event #{inspect(event)}")}
      end
    end
  end

  @doc """
  True only inside the wrapper. Anything else, a socket that was never set up
  included, is treated as not yet checked.
  """
  defguard is_wrapped(private)
           when is_map_key(private, :wrapped_in_authorization?) and
                  :erlang.map_get(:wrapped_in_authorization?, private) == true

  @doc """
  Checks the result of a wrapped callback, and hands the socket back unwrapped
  so the next callback is checked again.
  """
  def enforce!({:ok, socket}, module, callback), do: {:ok, enforce_socket!(socket, module, callback)}
  def enforce!({:ok, socket, opts}, module, callback), do: {:ok, enforce_socket!(socket, module, callback), opts}
  def enforce!({:noreply, socket}, module, callback), do: {:noreply, enforce_socket!(socket, module, callback)}

  def enforce!({:reply, reply, socket}, module, callback),
    do: {:reply, reply, enforce_socket!(socket, module, callback)}

  def enforce!({:cont, socket}, module, callback), do: {:cont, enforce_socket!(socket, module, callback)}
  def enforce!({:halt, socket}, module, callback), do: {:halt, enforce_socket!(socket, module, callback)}

  def enforce!({:halt, reply, socket}, module, callback), do: {:halt, reply, enforce_socket!(socket, module, callback)}

  @doc """
  Wraps the function given to `allow_upload/3` as `progress:`. The client
  drives it, like an event, so it has to state its authorization like one.

  A refusal is not rescued here. Nobody who may not upload gets an upload
  configured, so a refusal means the client made the upload up, and there is
  no entry to leave in a sensible state.
  """
  def authorized_progress(fun) when is_function(fun, 3) do
    {:module, module} = Function.info(fun, :module)
    {:name, name} = Function.info(fun, :name)

    fn upload, entry, socket ->
      upload
      |> fun.(entry, RequireAuthorization.wrap(socket))
      |> enforce!(module, "#{name}/3 for upload #{inspect(upload)}")
    end
  end

  defp enforce_socket!(socket, module, callback) do
    case check_socket_authorized(socket) do
      {:ok, socket} ->
        RequireAuthorization.unwrap(socket)

      {:error, AuthorizationFailed} ->
        raise AuthorizationFailed,
          message:
            "Authorization failed in `#{callback}` on #{inspect(module)}.\n\nAnnotation: #{inspect(socket.private[:authorization_info])}"

      {:error, AuthorizationNotApplied} ->
        raise AuthorizationNotApplied,
          message:
            "No authorization applied in `#{callback}` on #{inspect(module)}.\n\nA callback decorated with `authorizes_in_body/0` has to call `authorize!/3`. Otherwise use `@decorate` with `requires_permission/1`, `requires_permission/2`, `requires_no_permission/0` or `special_permission/1`."
    end
  end

  def check_socket_authorized(socket) do
    case socket do
      %{private: %{authorization_applied?: true, authorization_granted?: true}} ->
        {:ok, socket}

      %{private: %{authorization_applied?: true, authorization_granted?: false}} ->
        {:error, AuthorizationFailed}

      _other ->
        {:error, AuthorizationNotApplied}
    end
  end

  @doc false
  # True when the FunctionClauseError came from calling `module.fun/arity`
  # itself, and not from something that function called.
  def no_clause_for?(%FunctionClauseError{module: module, function: fun, arity: arity}, module, fun, arity, [
        {module, fun, args_or_arity, _location} | _
      ]) do
    args_or_arity == arity or (is_list(args_or_arity) and length(args_or_arity) == arity)
  end

  def no_clause_for?(_error, _module, _fun, _arity, _stacktrace), do: false

  @doc """
  The user was refused in an event. Keeps the socket from before the event and
  tells them.
  """
  def deny(socket, error, module, callback) do
    reraise_without_flash(socket, error)
    log_denied(socket, error, module, callback)

    put_flash(socket, :error, @denied_message)
  end

  @doc """
  The user was refused while a page was being set up. The assigns the template
  needs are missing, so send them somewhere that always renders.
  """
  def deny_navigation(socket, error, module, callback) do
    reraise_without_flash(socket, error)
    log_denied(socket, error, module, callback)

    socket
    |> put_flash(:error, @denied_message)
    |> redirect(to: "/")
  end

  @doc """
  The user was refused in a LiveComponent's event. A flash put on a
  component's socket is not shown, so the LiveView is asked to show it, which
  the hook attached in `RequireAuthorization.on_mount/4` does.
  """
  def deny_in_component(socket, error, module, callback) do
    log_denied(socket, error, module, callback)
    send(self(), RequireAuthorization.denied_message())

    socket
  end

  @doc false
  def denied_flash(), do: @denied_message

  # Unit tests call the callbacks with a bare socket that has no flash to put a
  # message in. Let those see the refusal itself.
  defp reraise_without_flash(%{assigns: assigns}, error) do
    if !Map.has_key?(assigns, :flash), do: raise(error)
  end

  defp log_denied(socket, error, module, callback) do
    user_id =
      case socket.assigns do
        %{current_scope: %{user: %{id: id}}} -> id
        _ -> nil
      end

    Logger.warning(
      "Authorization denied in #{callback} on #{inspect(module)} for user #{inspect(user_id)}: #{Exception.message(error)}"
    )
  end
end
