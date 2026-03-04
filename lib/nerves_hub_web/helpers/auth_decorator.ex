defmodule NervesHubWeb.Helpers.AuthDecorator do
  use Decorator.Define, requires_permission: 1, requires_no_permission: 0, special_permission: 1

  alias NervesHubWeb.Mounts.RequireAuthorization

  def requires_no_permission(body, %{args: [_event, _params, _socket]}) do
    quote(location: :keep) do
      {reply, socket} = unquote(body)

      {reply, RequireAuthorization.authorization_not_needed(socket)}
    end
  end

  def special_permission(reason, body, %{args: [_event, _params, _socket]}) do
    quote(location: :keep) do
      {reply, socket} = unquote(body)
      {reply, RequireAuthorization.confirm_user_is_authorized(unquote(reason), socket)}
    end
  end

  def requires_permission(permission, body, %{args: [_event, _params, socket]}) do
    quote(location: :keep) do
      %{private: private} = socket = RequireAuthorization.authorize!(unquote(socket), unquote(permission))
      {reply, socket} = unquote(body)
      authz = Map.take(private, [:authorization_applied?, :authorization_granted?, :authorization_info])
      socket = %{socket | private: Map.merge(socket.private, authz)}
      {reply, socket}
    end
  end
end
