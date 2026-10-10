defmodule NervesHubWeb.API.DeviceSharedSecretController do
  @moduledoc """
  A device's own shared secrets: its `nhd_` keys, as opposed to the product's
  `nhp_` keys that let any device register itself. For provisioning, where each
  device is given credentials of its own.

  Listing returns keys only and never secrets. Creating returns the secret
  exactly once, in that response, and it cannot be retrieved again.
  """
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Devices
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Plugs.RefuseDeletedDevice
  alias NervesHubWeb.API.Schemas.DeviceSharedSecretSchemas
  alias NervesHubWeb.API.Schemas.ErrorSchemas

  security([%{"bearer_auth" => []}])
  tags(["Device Shared Secrets"])

  @auth_error_responses SchemaHelpers.auth_error_responses()

  # Listing returns keys but never secrets, so view-only members may see them,
  # as they can a product's keys on its settings page.
  plug(:validate_role, [org: :manage] when action in [:create, :delete])
  plug(:validate_role, [org: :view] when action in [:index])
  plug(RefuseDeletedDevice when action in [:create, :delete])

  @device_path_parameters [
    org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
    product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"],
    identifier: [in: :path, description: "Device Identifier", type: :string, example: "example_device"]
  ]

  operation(:index,
    summary: "List a Device's Shared Secret Keys",
    description:
      "Lists every key the device has been given, deactivated ones included. Returns keys only. Secrets are never listed.",
    parameters: @device_path_parameters,
    responses:
      [
        ok:
          {"Device Shared Secret list response", "application/json",
           DeviceSharedSecretSchemas.DeviceSharedSecretListResponse}
      ] ++ @auth_error_responses
  )

  def index(%{assigns: %{device: device}} = conn, _params) do
    render(conn, :index, shared_secrets: Devices.list_shared_secret_auths(device))
  end

  operation(:create,
    summary: "Create a Shared Secret for a Device",
    description:
      "Creates a new key and secret the device can connect with. The secret is returned once, in this response, and cannot be retrieved again.",
    parameters: @device_path_parameters,
    responses:
      [
        created:
          {"Device Shared Secret create response", "application/json",
           DeviceSharedSecretSchemas.DeviceSharedSecretCreateResponse},
        unprocessable_entity: {"Unprocessable Entity", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def create(%{assigns: %{current_scope: %{user: user}, device: device}} = conn, _params) do
    with {:ok, auth} <- Devices.issue_shared_secret_auth(device, user) do
      conn
      |> put_status(:created)
      |> render(:created, shared_secret: auth)
    end
  end

  operation(:delete,
    summary: "Deactivate a Device's Shared Secret",
    description:
      "Deactivates one of the device's active keys, so the device can no longer connect with it. Returns not found for an unknown, already deactivated, or another device's key. The device is disconnected, since it may be connected with the key, and one with another active key reconnects with that. The key stays listed with its deactivation time.",
    parameters:
      @device_path_parameters ++
        [key: [in: :path, description: "Shared Secret Key", type: :string, example: "nhd_[43 URL-safe characters]"]],
    responses:
      [
        no_content: "Empty response",
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse},
        unprocessable_entity: {"Unprocessable Entity", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def delete(%{assigns: %{current_scope: %{user: user}, device: device}} = conn, %{"key" => key}) do
    with {:ok, _auth} <- Devices.deactivate_shared_secret_auth(device, key, user) do
      send_resp(conn, :no_content, "")
    end
  end
end
