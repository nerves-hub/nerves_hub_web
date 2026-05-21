defmodule NervesHubWeb.Access.AuthDecorator do
  use Decorator.Define, requires_permission: 1, requires_no_permission: 0, special_permission: 1

  alias __MODULE__
  alias NervesHubWeb.Mounts.RequireAuthorization

  @org_level_prefixes ~w(organization signing_key org_user certificate_authority)
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

  def requires_permission(permission, body, %{args: [_event, _params, socket_arg]}) do
    socket = socket_var(socket_arg)

    subject =
      if org_level_permission?(permission) do
        quote(do: unquote(socket).assigns.current_scope.org)
      else
        quote(do: unquote(socket).assigns.current_scope.product)
      end

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
