defmodule NervesHubWeb.API.UserController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHubWeb.API.Schemas.UserAuthRequest
  alias NervesHubWeb.API.Schemas.UserAuthWithNoteRequest
  alias NervesHubWeb.API.Schemas.UserResponse

  alias NervesHub.Accounts

  tags(["Auth"])

  operation(:me,
    summary: "Show details of the currently logged in user",
    responses: [
      ok: {"User response", "application/json", UserResponse}
    ],
    security: [%{}, %{"bearer_auth" => []}]
  )

  def me(%{assigns: %{user: user}} = conn, _params) do
    render(conn, :show, user: user)
  end

  operation(:auth,
    summary: "Authenticate a user",
    request_body: {"Authentication attributes", "application/json", UserAuthRequest, required: true},
    responses: [
      ok: {"User response", "application/json", UserResponse}
    ],
    security: []
  )

  def auth(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate(email, password) do
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

  def login(conn, %{"email" => email, "note" => note, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate(email, password) do
      token = Accounts.create_user_api_token(user, note)
      render(conn, :show, user: user, token: token)
    end
  end
end
