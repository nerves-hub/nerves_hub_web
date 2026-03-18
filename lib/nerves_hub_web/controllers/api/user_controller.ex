defmodule NervesHubWeb.API.UserController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Accounts
  alias NervesHubWeb.API.Schemas.ConsoleTokenResponse
  alias NervesHubWeb.API.Schemas.UserAuthRequest
  alias NervesHubWeb.API.Schemas.UserAuthWithNoteRequest
  alias NervesHubWeb.API.Schemas.UserResponse

  tags(["Auth"])

  operation(:me,
    summary: "Show details of the currently logged in user",
    responses: [
      ok: {"User response", "application/json", UserResponse}
    ],
    security: [%{}, %{"bearer_auth" => []}]
  )

  def me(%{assigns: %{current_scope: scope}} = conn, _params) do
    render(conn, :show, user: scope.user)
  end

  operation(:auth,
    summary: "Authenticate a user",
    request_body: {"Authentication attributes", "application/json", UserAuthRequest, required: true},
    responses: [
      ok: {"User response", "application/json", UserResponse}
    ],
    security: []
  )

  def auth(conn, assigns) do
    with {:ok, user} <- Accounts.authenticate(assigns["email"], assigns["password"]) do
      render(conn, :show, user: user)
    end
  end

  operation(:login,
    summary: "Authenticate a user (deprecated)",
    request_body: {"Authentication attributes", "application/json", UserAuthWithNoteRequest, required: true},
    responses: [
      ok: {"User response", "application/json", UserResponse}
    ],
    security: []
  )

  def login(conn, assigns) do
    with {:ok, user} <- Accounts.authenticate(assigns["email"], assigns["password"]) do
      token = Accounts.create_user_api_token(user, assigns["note"])
      render(conn, :show, user: user, token: token)
    end
  end

  operation(:console_token,
    summary: "Generate a token for connecting to the device console websocket (deprecated: pass your API token directly as the socket token param)",
    responses: [
      ok: {"Console token response", "application/json", ConsoleTokenResponse}
    ],
    security: [%{"bearer_auth" => []}],
    deprecated: true
  )

  def console_token(%{assigns: %{current_scope: scope}} = conn, _params) do
    token = Phoenix.Token.sign(NervesHubWeb.Endpoint, NervesHubWeb.user_salt(), scope.user.id)
    render(conn, :console_token, token: token)
  end
end
