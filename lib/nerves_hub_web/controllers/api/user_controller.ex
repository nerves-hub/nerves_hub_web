defmodule NervesHubWeb.API.UserController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Accounts
  alias NervesHubWeb.API.Schemas.ErrorSchemas
  alias NervesHubWeb.API.Schemas.UserAuthCLISessionRequest
  alias NervesHubWeb.API.Schemas.UserAuthCLISessionResponse
  alias NervesHubWeb.API.Schemas.UserAuthCLISessionStatusResponse
  alias NervesHubWeb.API.Schemas.UserAuthWithNoteRequest
  alias NervesHubWeb.API.Schemas.UserResponse
  alias NervesHubWeb.Plugs.Attack

  plug(Attack when action in [:check_cli_session])

  tags(["Auth"])

  operation(:me,
    summary: "Show details of the currently logged in user",
    responses: [
      ok: {"User response", "application/json", UserResponse},
      unauthorized: {"Unauthorized", "application/json", ErrorSchemas.ErrorResponse}
    ],
    security: [%{}, %{"bearer_auth" => []}]
  )

  def me(%{assigns: %{current_scope: scope}} = conn, _params) do
    render(conn, :show, user: scope.user)
  end

  operation(:auth,
    summary: "Authenticate a user",
    request_body: {"Authentication attributes", "application/json", UserAuthWithNoteRequest, required: true},
    responses: [
      ok: {"User response", "application/json", UserResponse},
      unauthorized: {"Unauthorized", "application/json", ErrorSchemas.ErrorResponse}
    ],
    security: []
  )

  def auth(conn, assigns) do
    with {:ok, user} <- Accounts.authenticate(assigns["email"], assigns["password"]) do
      token = Accounts.create_user_api_token(user, assigns["note"])
      render(conn, :show, user: user, token: token)
    end
  end

  operation(:login,
    summary: "Authenticate a user (deprecated)",
    request_body: {"Authentication attributes", "application/json", UserAuthWithNoteRequest, required: true},
    responses: [
      ok: {"User response", "application/json", UserResponse},
      unauthorized: {"Unauthorized", "application/json", ErrorSchemas.ErrorResponse}
    ],
    security: []
  )

  def login(conn, params) do
    with {:ok, user} <- Accounts.authenticate(params["email"], params["password"]) do
      token = Accounts.create_user_api_token(user, params["note"])
      render(conn, :show, user: user, token: token)
    end
  end

  operation(:cli_session,
    summary: "Start the CLI authentication process",
    request_body: {"CLI Session attributes", "application/json", UserAuthCLISessionRequest},
    responses: [
      ok: {"Auth CLI session token response", "application/json", UserAuthCLISessionResponse}
    ],
    security: []
  )

  def cli_session(conn, params) do
    Accounts.generate_cli_session_token(params["note"])
    |> case do
      {:ok, cli_session} ->
        render(conn,
          token: cli_session.token,
          url: url(conn, ~p"/auth/cli/#{cli_session.token}"),
          confirmation_code: cli_session.confirmation_code
        )

      {:error, :invalid_request} ->
        raise NervesHubWeb.InvalidRequestError, info: "token invalid"
    end
  end

  operation(:check_cli_session,
    summary: "Check the CLI authentication progress",
    parameters: [
      token: [
        in: :path,
        description: "CLI Session Token",
        type: :string,
        example: "abc123token"
      ]
    ],
    responses: [
      ok: {"Auth CLI session token response", "application/json", UserAuthCLISessionStatusResponse},
      not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
    ],
    security: []
  )

  def check_cli_session(conn, %{"token" => token}) do
    Accounts.check_cli_session_ready(token)
    |> case do
      {:ok, %{status: :waiting}} ->
        render(conn, status: :waiting)

      {:ok, cli_session} ->
        render(conn, status: :ready, user_token: cli_session.user_token)

      {:error, :not_found} ->
        raise NervesHubWeb.NotFoundError
    end
  end
end
