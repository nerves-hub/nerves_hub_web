defmodule NervesHubWeb.AuthDecorator do
  use Decorator.Define, requires_permission: 1

  def requires_permission(permission, body, %{args: [_event, _params, socket]}) do
    quote(location: :keep) do
      if authorized?(unquote(permission), unquote(socket).assigns.current_scope) do
        unquote(body)
      else
        unquote(socket)
        |> put_flash(:error, "Sorry, you don't have the required role")
        |> noreply()
      end
    end
  end
end
