defmodule NervesHubWeb.API.KeyController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgKey
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.ErrorSchemas
  alias NervesHubWeb.API.Schemas.KeySchemas

  security([%{"bearer_auth" => []}])
  tags(["Signing Keys"])

  @auth_error_responses SchemaHelpers.auth_error_responses()

  plug(:validate_role, [org: :manage] when action in [:create, :delete])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  operation(:index,
    summary: "List all Firmware and Archive Signing Keys for an Organization",
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
        ok: {"Signing Keys", "application/json", KeySchemas.SigningKeyIndexResponse}
      ] ++ @auth_error_responses
  )

  def index(%{assigns: %{current_scope: scope}} = conn, _params) do
    keys = Accounts.list_org_keys(scope)
    render(conn, :index, keys: keys)
  end

  operation(:create,
    summary: "Create a new Signing Key for an Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ]
    ],
    request_body: {
      "Signing Key creation request body",
      "application/json",
      KeySchemas.SigningKeyCreationRequest,
      required: true
    },
    responses:
      [
        created: {"Signing Key", "application/json", KeySchemas.SigningKeyShowResponse},
        unprocessable_entity: {"Unprocessable Entity", "application/json", ErrorSchemas.ChangesetErrorResponse}
      ] ++ @auth_error_responses
  )

  def create(%{assigns: %{current_scope: %{user: user, org: org}}} = conn, params) do
    params =
      Map.take(params, ["name", "key"])
      |> Map.put("org_id", org.id)
      |> Map.put("created_by_id", user.id)

    with {:ok, key} <- Accounts.create_org_key(params) do
      conn
      |> put_status(:created)
      |> render(:show, key: key)
    end
  end

  operation(:show,
    summary: "Show a Signing Key for an Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      name: [
        in: :path,
        description: "Signing Key Name",
        type: :string,
        example: "example_key"
      ]
    ],
    responses:
      [
        ok: {"Signing Key", "application/json", KeySchemas.SigningKeyShowResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def show(%{assigns: %{current_scope: %{org: org}}} = conn, %{"name" => name}) do
    with {:ok, key} <- Accounts.get_org_key_by_name(org, name) do
      render(conn, :show, key: key)
    end
  end

  operation(:delete,
    summary: "Delete a Signing Key for an Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      name: [
        in: :path,
        description: "Signing Key Name",
        type: :string,
        example: "example_key"
      ]
    ],
    responses:
      [
        no_content: "Empty response",
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def delete(%{assigns: %{current_scope: %{org: org}}} = conn, %{"name" => name}) do
    with {:ok, key} <- Accounts.get_org_key_by_name(org, name),
         {:ok, %OrgKey{}} <- Accounts.delete_org_key(key) do
      send_resp(conn, :no_content, "")
    end
  end
end
