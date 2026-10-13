defmodule NervesHubWeb.API.WebhookController do
  @moduledoc """
  A product's webhooks: the endpoints its device events are sent to. The
  same webhooks the product's Integrations settings manage; see
  `NervesHub.Webhooks` and `docs/webhooks.md`.

  Every action needs the manage role, reading included. On the settings page,
  view-only members see a webhook's host but not its URL, because some
  receivers carry their credentials in the URL. An API response has no
  halfway, so it is all or nothing.

  The signing secret is returned when a webhook is created and when its
  secret is regenerated, and never listed. A caller that has lost it
  regenerates it.
  """
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Webhooks
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.ErrorSchemas
  alias NervesHubWeb.API.Schemas.WebhookSchemas

  security([%{"bearer_auth" => []}])
  tags(["Webhooks"])

  @auth_error_responses SchemaHelpers.auth_error_responses()

  plug(:validate_role, org: :manage)

  @product_path_parameters [
    org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
    product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"]
  ]

  @webhook_path_parameters @product_path_parameters ++
                             [id: [in: :path, description: "Webhook ID", type: :integer, example: 12]]

  @not_found {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
  @unprocessable {"Unprocessable Entity", "application/json", ErrorSchemas.ChangesetErrorResponse}

  operation(:index,
    summary: "List a Product's Webhooks",
    description: "Lists the product's webhooks, oldest first, without their signing secrets.",
    parameters: @product_path_parameters,
    responses:
      [ok: {"Webhook list response", "application/json", WebhookSchemas.WebhookListResponse}] ++
        @auth_error_responses
  )

  def index(%{assigns: %{current_scope: scope}} = conn, _params) do
    render(conn, :index, webhooks: Webhooks.list_webhooks(scope.product))
  end

  operation(:show,
    summary: "Get a Webhook",
    description: "Includes the webhook's delivery state, such as when it started failing, but not its signing secret.",
    parameters: @webhook_path_parameters,
    responses:
      [ok: {"Webhook response", "application/json", WebhookSchemas.WebhookResponse}, not_found: @not_found] ++
        @auth_error_responses
  )

  def show(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with {:ok, webhook} <- Webhooks.fetch_webhook(scope.product, id) do
      render(conn, :show, webhook: webhook)
    end
  end

  operation(:create,
    summary: "Add a Webhook to a Product",
    description:
      "Creates a webhook with a newly generated signing secret, returned once, in this response. A product can have at most #{Webhooks.max_webhooks_per_product()} webhooks.",
    parameters: @product_path_parameters,
    request_body:
      {"Webhook creation request body", "application/json", WebhookSchemas.WebhookCreateRequest, required: true},
    responses:
      [
        created: {"Webhook with secret response", "application/json", WebhookSchemas.WebhookWithSecretResponse},
        unprocessable_entity: @unprocessable
      ] ++ @auth_error_responses
  )

  def create(%{assigns: %{current_scope: scope}} = conn, params) do
    with {:ok, webhook} <- Webhooks.create_webhook(scope, params) do
      conn
      |> put_status(:created)
      |> render(:with_secret, webhook: webhook)
    end
  end

  operation(:update,
    summary: "Update a Webhook",
    description:
      "Changes a webhook's URL, description, events, or whether it is on. The signing secret is not changed.",
    parameters: @webhook_path_parameters,
    request_body:
      {"Webhook update request body", "application/json", WebhookSchemas.WebhookUpdateRequest, required: true},
    responses:
      [
        ok: {"Webhook response", "application/json", WebhookSchemas.WebhookResponse},
        not_found: @not_found,
        unprocessable_entity: @unprocessable
      ] ++ @auth_error_responses
  )

  def update(%{assigns: %{current_scope: scope}} = conn, %{"id" => id} = params) do
    with {:ok, webhook} <- Webhooks.fetch_webhook(scope.product, id),
         {:ok, webhook} <- Webhooks.update_webhook(scope, webhook, params) do
      render(conn, :show, webhook: webhook)
    end
  end

  operation(:delete,
    summary: "Delete a Webhook",
    description: "Removes the webhook. Deliveries already queued for it are dropped.",
    parameters: @webhook_path_parameters,
    responses: [no_content: "Empty response", not_found: @not_found] ++ @auth_error_responses
  )

  def delete(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with {:ok, webhook} <- Webhooks.fetch_webhook(scope.product, id),
         {:ok, _webhook} <- Webhooks.delete_webhook(scope, webhook) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:regenerate_secret,
    summary: "Regenerate a Webhook's Signing Secret",
    description:
      "Replaces the signing secret and returns the new one, once, in this response. The old secret stops working at once, retries of earlier events included.",
    parameters: @webhook_path_parameters,
    responses:
      [
        ok: {"Webhook with secret response", "application/json", WebhookSchemas.WebhookWithSecretResponse},
        not_found: @not_found
      ] ++ @auth_error_responses
  )

  def regenerate_secret(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with {:ok, webhook} <- Webhooks.fetch_webhook(scope.product, id),
         {:ok, webhook} <- Webhooks.regenerate_secret(scope, webhook) do
      render(conn, :with_secret, webhook: webhook)
    end
  end

  operation(:send_test,
    summary: "Send a Test Event to a Webhook",
    description:
      "Sends a `webhook.test` event to the webhook straight away, whether or not it is on, and reports how the endpoint answered. Responds 200 either way: `delivered` says whether the endpoint accepted it. Takes up to 20 seconds when the endpoint is slow. The result is not recorded against the webhook.",
    parameters: @webhook_path_parameters,
    responses:
      [
        ok: {"Webhook test response", "application/json", WebhookSchemas.WebhookTestResponse},
        not_found: @not_found
      ] ++ @auth_error_responses
  )

  def send_test(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with {:ok, webhook} <- Webhooks.fetch_webhook(scope.product, id) do
      render(conn, :test_result, result: Webhooks.send_test_event(scope, webhook))
    end
  end
end
