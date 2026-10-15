defmodule NervesHubWeb.API.ArchiveController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Archives
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.ArchiveSchemas
  alias NervesHubWeb.API.Schemas.ErrorSchemas

  plug(:validate_role, [org: :manage] when action in [:create, :download])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  tags(["Archives"])
  security([%{"bearer_auth" => []}])

  @auth_error_responses SchemaHelpers.auth_error_responses()

  operation(:index,
    summary: "List all Archives for a Product",
    parameters: [
      org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
      product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"]
    ],
    responses:
      [
        ok: {"Archive list response", "application/json", ArchiveSchemas.ArchiveListResponse}
      ] ++ @auth_error_responses
  )

  def index(%{assigns: %{product: product}} = conn, _params) do
    render(conn, :index, archives: Archives.all_by_product(product))
  end

  operation(:create,
    summary: "Upload an Archive for a Product",
    description: """
    Accepts an fwup archive (`.fw`) signed against an Ed25519 key registered to
    the organization. Its `meta-version` must be SemVer.
    """,
    parameters: [
      org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
      product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"]
    ],
    request_body: {"Archive file upload", "multipart/form-data", nil},
    responses:
      [
        created: {"Archive response", "application/json", ArchiveSchemas.ArchiveResponse},
        unprocessable_entity: {"Upload rejected", "application/json", ArchiveSchemas.ArchiveUploadErrorResponse}
      ] ++ @auth_error_responses
  )

  def create(%{assigns: %{current_scope: %{org: org}, product: product}} = conn, params) do
    with {%{path: filepath}, _params} <- Map.pop(params, "archive"),
         {:ok, archive} <- Archives.create(product, filepath) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.api_archive_path(conn, :show, org, product.name, archive.uuid))
      |> render(:show, archive: archive)
    else
      {nil, %{}} -> {:error, {:no_archive_uploaded, "No archive uploaded"}}
      error -> error
    end
  end

  operation(:show,
    summary: "Show an Archive",
    parameters: [
      org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
      product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"],
      uuid: [in: :path, description: "Archive UUID", type: :string, example: "d9f8c63a-1234-5678-abcd-ef0123456789"]
    ],
    responses:
      [
        ok: {"Archive response", "application/json", ArchiveSchemas.ArchiveResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def show(%{assigns: %{product: product}} = conn, %{"uuid" => uuid}) do
    with {:ok, archive} <- Archives.get(product, uuid) do
      render(conn, :show, archive: archive)
    end
  end

  operation(:download,
    summary: "Download an Archive",
    parameters: [
      org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
      product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"],
      uuid: [in: :path, description: "Archive UUID", type: :string, example: "d9f8c63a-1234-5678-abcd-ef0123456789"]
    ],
    responses:
      [
        found: "Redirect to archive download URL",
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def download(%{assigns: %{product: product}} = conn, %{"uuid" => uuid}) do
    with {:ok, archive} <- Archives.get(product, uuid) do
      redirect(conn, external: Archives.url(archive))
    end
  end
end
