defmodule NervesHubWeb.API.ProductController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.ErrorSchemas
  alias NervesHubWeb.API.Schemas.ProductSchemas

  tags(["Products"])
  security([%{"bearer_auth" => []}])

  @auth_error_responses SchemaHelpers.auth_error_responses()

  plug(:validate_role, [org: :admin] when action in [:create, :delete])
  plug(:validate_role, [org: :view] when action in [:show])

  operation(:index,
    summary: "List all Products for an Organization",
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
        ok: {"Product list response", "application/json", ProductSchemas.ProductListResponse}
      ] ++ @auth_error_responses
  )

  def index(%{assigns: %{current_scope: scope}} = conn, _params) do
    products = Products.get_products(scope)
    render(conn, :index, products: products)
  end

  operation(:create,
    summary: "Create a new Product in an Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ]
    ],
    request_body: {
      "Product creation request body",
      "application/json",
      ProductSchemas.ProductCreationRequest,
      required: true
    },
    responses:
      [
        created: {"Product response", "application/json", ProductSchemas.ProductShowResponse},
        unprocessable_entity: {"Unprocessable Entity", "application/json", ErrorSchemas.ChangesetErrorResponse}
      ] ++ @auth_error_responses
  )

  def create(%{assigns: %{current_scope: %{org: org}}} = conn, params) do
    params =
      params
      |> Map.take(["name"])
      |> Map.put("org_id", org.id)

    with {:ok, product} <- Products.create_product(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.api_product_path(conn, :show, org.name, product.name))
      |> render(:show, product: product)
    end
  end

  operation(:show,
    summary: "Retrieves a Products details",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      product_name: [
        in: :path,
        description: "Product Name",
        type: :string,
        example: "example_product"
      ]
    ],
    responses:
      [
        ok: {"Product response", "application/json", ProductSchemas.ProductShowResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def show(%{assigns: %{product: product}} = conn, _params) do
    render(conn, :show, product: product)
  end

  operation(:delete,
    summary: "Delete an Organizations Product",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      product_name: [
        in: :path,
        description: "Product Name",
        type: :string,
        example: "example_product"
      ]
    ],
    responses:
      [
        no_content: "Empty response",
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def delete(%{assigns: %{product: product}} = conn, _params) do
    with {:ok, %Product{}} <- Products.delete_product(product) do
      send_resp(conn, :no_content, "")
    end
  end
end
