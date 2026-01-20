defmodule NervesHubWeb.API.OrgUserController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserNotifier

  alias NervesHubWeb.API.Schemas.OrgUserSchemas

  plug(:validate_role, org: :admin)

  security([%{}, %{"bearer_auth" => []}])
  tags(["Organization Members"])

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
    responses: [
      ok: {"Organization users list response", "application/json", OrgUserSchemas.OrgUserListResponse}
    ]
  )

  def index(%{assigns: %{org: org}} = conn, _params) do
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
    responses: [
      ok: {"Organization User", "application/json", OrgUserSchemas.OrgUser}
    ]
  )

  def add(%{assigns: %{org: org}} = conn, %{"email" => email} = params) do
    with {:ok, role} <- Map.fetch(params, "role"),
         {:user, {:ok, user}} <- {:user, Accounts.get_user_by_email(email)},
         {:ok, org_user} <- Accounts.add_org_user(org, user, %{role: role}) do
      # Let every other admin in the organization know about this new user.
      instigator = conn.assigns.user

      _ = UserNotifier.deliver_all_tell_org_user_added(org, instigator, user)

      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.api_org_user_path(conn, :show, org.name, user.email)
      )
      |> render(:show, org_user: org_user)
    else
      {:user, {:error, :not_found}} ->
        {:error, :org_user_not_found}

      error ->
        error
    end
  end

  def add(_conn, _params) do
    :error
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
    responses: [
      no_content: "Empty response"
    ]
  )

  def invite(%{assigns: %{org: org, user: invited_by}} = conn, %{"email" => email} = params) do
    with {:ok, role} <- Map.fetch(params, "role"),
         {:user, {:error, :not_found}} <- {:user, Accounts.get_user_by_email(email)},
         {:ok, invite} <- Accounts.invite(%{"email" => email, "role" => role}, org, invited_by) do
      invite_url = url(~p"/invite/#{invite.token}")

      # Let every other admin in the organization know about this new user.

      _ = UserNotifier.deliver_user_invite(invite.email, org, invited_by, invite_url)
      _ = UserNotifier.deliver_all_tell_org_user_invited(org, invited_by, invite.email)

      conn
      |> put_status(:created)
      |> send_resp(:no_content, "")
    else
      {:user, {:ok, _}} ->
        {:error, :org_user_exists}

      error ->
        error
    end
  end

  def invite(_conn, _params) do
    :error
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
    responses: [
      ok: {"Organization User", "application/json", OrgUserSchemas.OrgUser}
    ]
  )

  def show(%{assigns: %{org: org}} = conn, %{"user_email" => user_email}) do
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
    responses: [
      no_content: "Empty response"
    ]
  )

  def remove(%{assigns: %{org: org, actor: actor}} = conn, %{"user_email" => user_email}) do
    with {:ok, user_to_remove} <- Accounts.get_user_by_email(user_email),
         {:ok, _org_user} <- Accounts.get_org_user(org, user_to_remove),
         :ok <- Accounts.remove_org_user(org, user_to_remove) do
      # Now let every admin in the organization - except the admin who undertook the action
      # that this user has been removed from the organization.
      _ = UserNotifier.deliver_all_tell_org_user_removed(org, actor, user_to_remove)

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
    responses: [
      ok: {"Organization User", "application/json", OrgUserSchemas.OrgUser}
    ]
  )

  def update(%{assigns: %{org: org}} = conn, %{"user_email" => user_email} = params) do
    with {:ok, user} <- Accounts.get_user_by_email(user_email),
         {:ok, org_user} <- Accounts.get_org_user(org, user),
         {:ok, role} <- Map.fetch(params, "role"),
         {:ok, org_user} <- Accounts.change_org_user_role(org_user, role) do
      render(conn, :show, org_user: org_user)
    end
  end
end
