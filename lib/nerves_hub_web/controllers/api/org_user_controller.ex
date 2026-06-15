defmodule NervesHubWeb.API.OrgUserController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserNotifier
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.ErrorSchemas
  alias NervesHubWeb.API.Schemas.OrgUserSchemas

  plug(:validate_role, org: :admin)

  security([%{"bearer_auth" => []}])
  tags(["Organization Members"])

  @auth_error_responses SchemaHelpers.auth_error_responses()

  operation(:index,
    summary: "List all members of an Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ]
    ],
    responses:
      [
        ok: {"Organization users list response", "application/json", OrgUserSchemas.OrgUserListResponse}
      ] ++ @auth_error_responses
  )

  def index(%{assigns: %{current_scope: %{org: org}}} = conn, _params) do
    org_users = Accounts.get_org_users(org)
    render(conn, :index, org_users: org_users)
  end

  operation(:add,
    summary: "Add a user to an Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ]
    ],
    request_body: {
      "Org User creation request body",
      "application/json",
      OrgUserSchemas.OrgUserCreationRequest,
      required: true
    },
    responses:
      [
        created:
          {"Organization User - User is added to the organization", "application/json",
           OrgUserSchemas.OrgUserShowResponse},
        no_content: "Empty response - User is invited to the organization"
      ] ++ @auth_error_responses,
    deprecated: true
  )

  def add(conn, params) do
    invite(conn, params)
  end

  operation(:invite,
    summary: "Invite a user to the Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ]
    ],
    request_body: {
      "Org User creation request body",
      "application/json",
      OrgUserSchemas.OrgUserCreationRequest,
      required: true
    },
    responses:
      [
        created:
          {"Organization User - User is added to the organization", "application/json",
           OrgUserSchemas.OrgUserShowResponse},
        no_content: "Empty response - User is invited to the organization"
      ] ++ @auth_error_responses
  )

  def invite(%{assigns: %{current_scope: %{user: invited_by, org: org}}} = conn, %{"email" => email, "role" => role}) do
    # if a user exists in the system, add them to the organization
    # otherwise, invite them to the organization and to NervesHub
    case Accounts.get_user_by_email(email) do
      {:ok, user} ->
        add_user(conn, org, user, role, invited_by)

      {:error, :not_found} ->
        invite_user(conn, org, email, role, invited_by)
    end
  end

  def invite(_conn, _params) do
    :error
  end

  defp add_user(conn, org, user, role, invited_by) do
    with {:ok, org_user} <- Accounts.add_org_user(org, user, %{role: role}) do
      _ = UserNotifier.deliver_all_tell_org_user_added(org, invited_by, user)

      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/orgs/#{org.name}/users/#{user.email}")
      |> render(:show, org_user: org_user)
    end
  end

  defp invite_user(conn, org, email, role, invited_by) do
    with {:ok, invite} <- Accounts.invite(%{"email" => email, "role" => role}, org, invited_by) do
      invite_url = url(~p"/invite/#{invite.token}")

      # Let every other admin in the organization know about this new user.

      _ = UserNotifier.deliver_user_invite(invite.email, org, invited_by, invite_url)
      _ = UserNotifier.deliver_all_tell_org_user_invited(org, invited_by, invite.email)

      conn
      |> put_status(:created)
      |> send_resp(:no_content, "")
    end
  end

  operation(:show,
    summary: "Show membership details of a user in an Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      user_email: [
        in: :path,
        description: "User Email",
        type: :string,
        example: "jane@person.com"
      ]
    ],
    responses:
      [
        ok: {"Organization User", "application/json", OrgUserSchemas.OrgUserShowResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def show(%{assigns: %{current_scope: %{org: org}}} = conn, %{"user_email" => user_email}) do
    with {:ok, user} <- Accounts.get_user_by_email(user_email),
         {:ok, org_user} <- Accounts.get_org_user(org, user) do
      render(conn, :show, org_user: org_user)
    end
  end

  operation(:remove,
    summary: "Remove a user from an Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      user_email: [
        in: :path,
        description: "User Email",
        type: :string,
        example: "jane@person.com"
      ]
    ],
    responses:
      [
        no_content: "Empty response",
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def remove(%{assigns: %{current_scope: %{user: user, org: org}}} = conn, %{"user_email" => user_email}) do
    with {:ok, user_to_remove} <- Accounts.get_user_by_email(user_email),
         {:ok, _org_user} <- Accounts.get_org_user(org, user_to_remove),
         :ok <- Accounts.remove_org_user(org, user_to_remove) do
      # Now let every admin in the organization - except the admin who undertook the action
      # that this user has been removed from the organization.
      _ = UserNotifier.deliver_all_tell_org_user_removed(org, user, user_to_remove)

      send_resp(conn, :no_content, "")
    end
  end

  operation(:update,
    summary: "Update a user's role in an Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      user_email: [
        in: :path,
        description: "User Email",
        type: :string,
        example: "jane@person.com"
      ]
    ],
    request_body: {
      "Org User update request body",
      "application/json",
      OrgUserSchemas.OrgUserUpdateRequest,
      required: true
    },
    responses:
      [
        ok: {"Organization User", "application/json", OrgUserSchemas.OrgUserShowResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse},
        unprocessable_entity: {"Unprocessable Entity", "application/json", ErrorSchemas.ChangesetErrorResponse}
      ] ++ @auth_error_responses
  )

  def update(%{assigns: %{current_scope: %{org: org}}} = conn, %{"user_email" => user_email} = params) do
    with {:ok, user} <- Accounts.get_user_by_email(user_email),
         {:ok, org_user} <- Accounts.get_org_user(org, user),
         {:ok, role} <- Map.fetch(params, "role"),
         {:ok, org_user} <- Accounts.change_org_user_role(org_user, role) do
      render(conn, :show, org_user: org_user)
    end
  end
end
