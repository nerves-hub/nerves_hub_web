defmodule NervesHubWeb.Access.AuthDecorator do
  use Decorator.Define, requires_permission: 1, requires_no_permission: 0, special_permission: 1

  alias NervesHubWeb.Mounts.RequireAuthorization

  @org_level_prefixes ~w(organization signing_key org_user certificate_authority)
  @org_level_permissions [:"product:create"]

  def requires_no_permission(body, %{args: [_event, _params, _socket]}) do
    quote(location: :keep) do
      {reply, socket} = unquote(body)

      {reply, RequireAuthorization.authorization_not_needed(socket)}
    end
  end

  def special_permission(reason, body, %{args: [_event, _params, _socket]}) do
    quote(location: :keep) do
      {reply, socket} = unquote(body)
      {reply, RequireAuthorization.confirm_user_is_authorized(socket, unquote(reason))}
    end
  end

  def requires_permission(permission, body, %{args: [_event, _params, socket]}) do
    subject =
      if org_level_permission?(permission) do
        quote(do: unquote(socket).assigns.current_scope.org)
      else
        quote(do: unquote(socket).assigns.current_scope.product)
      end

    quote(location: :keep) do
      %{private: private} =
        socket = RequireAuthorization.authorize!(unquote(socket), unquote(permission), unquote(subject))

      {reply, socket} = unquote(body)
      authz = Map.take(private, [:authorization_applied?, :authorization_granted?, :authorization_info])
      socket = %{socket | private: Map.merge(socket.private, authz)}
      {reply, socket}
    end
  end

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
