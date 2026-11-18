defmodule NervesHubWeb.API.Plugs.RequireAuthenticatedUserOrApiKey do
  @moduledoc """
  Lets through a request made with a user API token or a product API key.

  Only for the routes about one product or one device. A key reaches nothing
  about an organization or a user, so those routes keep
  `NervesHubWeb.API.Plugs.RequireAuthenticatedUser`.

  What the request may then do is decided the same way for both: the scope
  carries the role's permissions, and the controller's
  `NervesHubWeb.Helpers.PermissionPlugs` check them.
  """

  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.Products.ApiKey

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    case conn.assigns.current_scope do
      %Scope{user: %User{}} -> conn
      %Scope{api_key: %ApiKey{}} -> conn
      _ -> raise NervesHubWeb.UnauthorizedError
    end
  end
end
