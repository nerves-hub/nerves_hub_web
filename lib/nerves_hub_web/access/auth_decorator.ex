defmodule NervesHubWeb.Access.AuthDecorator do
  @moduledoc """
  The decorators a LiveView, LiveComponent or device page tab uses to state
  what a callback needs before it may run.

    * `@decorate requires_permission(:"device:list")` checks the permission
      against the product in the scope (or the org, for org-level
      permissions) before the body runs.
    * `@decorate requires_permission(:"device:update", on: :device)` checks it
      against `socket.assigns.device`, so the role has to hold for that
      record and not merely somewhere.
    * `@decorate authorizes_in_body()` is for a callback that has to load the
      record first. The body must call `authorize!/3`; the wrapper refuses the
      result if it did not.
    * `@decorate requires_no_permission()` and
      `@decorate special_permission(reason)` state that there is nothing to
      check, and why.

  Every clause of a checked callback needs one of these. A clause without one
  does not compile, see `NervesHubWeb.Access.AuthorizationDeclared`.
  """

  use Decorator.Define,
    requires_permission: 1,
    requires_permission: 2,
    requires_no_permission: 0,
    special_permission: 1,
    authorizes_in_body: 0

  alias __MODULE__
  alias NervesHubWeb.Mounts.RequireAuthorization

  @org_level_prefixes ~w(organization signing_key org_user certificate_authority network_identity webhook slack_connection slack_subscription chat_webhook)
  @org_level_permissions [:"product:create"]

  @authz_keys [:authorization_applied?, :authorization_granted?, :authorization_info]

  def requires_no_permission(body, %{args: [_event, _params, _socket]}) do
    quote(location: :keep) do
      unquote(body)
      |> AuthDecorator.mark_socket(fn sock ->
        RequireAuthorization.authorization_not_needed(sock)
      end)
    end
  end

  def special_permission(reason, body, %{args: [_event, _params, _socket]}) do
    quote(location: :keep) do
      unquote(body)
      |> AuthDecorator.mark_socket(fn sock ->
        RequireAuthorization.confirm_user_is_authorized(sock, unquote(reason))
      end)
    end
  end

  # The body states its own authorization with `authorize!/3`. Nothing is added
  # here: the wrapper around the callback checks that it happened.
  def authorizes_in_body(body, %{args: [_event, _params, _socket]}), do: body

  def requires_permission(permission, body, %{args: [_event, _params, socket_arg]} = context) do
    socket = socket_var(socket_arg)

    subject =
      if org_level_permission?(permission) do
        quote(do: unquote(socket).assigns.current_scope.org)
      else
        quote(do: unquote(socket).assigns.current_scope.product)
      end

    check_before(permission, subject, body, context)
  end

  def requires_permission(permission, [on: assign], body, %{args: [_event, _params, socket_arg]} = context)
      when is_atom(assign) do
    socket = socket_var(socket_arg)

    check_before(permission, quote(do: Map.fetch!(unquote(socket).assigns, unquote(assign))), body, context)
  end

  defp check_before(permission, subject, body, %{args: [_event, _params, socket_arg]}) do
    socket = socket_var(socket_arg)

    quote(location: :keep) do
      authz_socket =
        RequireAuthorization.authorize!(unquote(socket), unquote(permission), unquote(subject))

      authz = Map.take(authz_socket.private, unquote(@authz_keys))

      unquote(body)
      |> AuthDecorator.mark_socket(fn sock ->
        %{sock | private: Map.merge(sock.private, authz)}
      end)
    end
  end

  # Extract the bare socket variable from an arg AST. The arg may be a plain
  # variable (`socket`) or a pattern match (`%{...} = socket` / `socket = %{...}`).
  # Without this, `unquote(socket_arg)` would re-inject the pattern and shadow
  # any variables it binds.
  defp socket_var({:=, _, [{name, _, ctx} = var, _]}) when is_atom(name) and is_atom(ctx), do: var
  defp socket_var({:=, _, [_, {name, _, ctx} = var]}) when is_atom(name) and is_atom(ctx), do: var
  defp socket_var({name, _, ctx} = var) when is_atom(name) and is_atom(ctx), do: var

  @doc false
  def mark_socket({:noreply, sock}, fun), do: {:noreply, fun.(sock)}
  def mark_socket({:reply, reply, sock}, fun), do: {:reply, reply, fun.(sock)}
  def mark_socket({:ok, sock}, fun), do: {:ok, fun.(sock)}
  def mark_socket({:ok, sock, opts}, fun), do: {:ok, fun.(sock), opts}
  def mark_socket({:halt, sock}, fun), do: {:halt, fun.(sock)}
  def mark_socket({:halt, reply, sock}, fun), do: {:halt, reply, fun.(sock)}
  def mark_socket({:cont, sock}, fun), do: {:cont, fun.(sock)}

  defp org_level_permission?(permission) do
    permission in @org_level_permissions or
      prefix_is_org_level?(permission)
  end

  defp prefix_is_org_level?(permission) do
    prefix =
      permission
      |> Atom.to_string()
      |> String.split(":")
      |> hd()

    prefix in @org_level_prefixes
  end
end
