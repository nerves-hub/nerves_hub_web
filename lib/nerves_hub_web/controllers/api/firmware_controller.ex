defmodule NervesHubWeb.API.FirmwareController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Firmwares
  alias NervesHub.Repo
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.ErrorSchemas
  alias NervesHubWeb.API.Schemas.FirmwareSchemas

  require Logger

  plug(:validate_role, [org: :manage] when action in [:create, :delete, :download])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  tags(["Firmwares"])
  security([%{"bearer_auth" => []}])

  @auth_error_responses SchemaHelpers.auth_error_responses()

  operation(:index,
    summary: "List all Firmwares for a Product",
    parameters: [
      org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
      product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"]
    ],
    responses:
      [
        ok: {"Firmware list response", "application/json", FirmwareSchemas.FirmwareListResponse}
      ] ++ @auth_error_responses
  )

  def index(%{assigns: %{product: product}} = conn, _params) do
    firmwares = Firmwares.get_firmwares_by_product(product.id)
    render(conn, :index, firmwares: firmwares)
  end

  operation(:create,
    summary: "Upload a Firmware for a Product",
    parameters: [
      org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
      product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"]
    ],
    request_body: {"Firmware file upload", "multipart/form-data", nil},
    responses:
      [
        created: {"Firmware response", "application/json", FirmwareSchemas.FirmwareResponse},
        unprocessable_entity: {"Unprocessable Entity", "application/json", ErrorSchemas.ChangesetErrorResponse}
      ] ++ @auth_error_responses
  )

  def create(%{assigns: %{current_scope: %{org: org}, product: product}} = conn, params) do
    Logger.info("System Memory:" <> inspect(:memsup.get_system_memory_data()))

    with {%{path: filepath}, _params} <- Map.pop(params, "firmware"),
         {:ok, firmware} <- Firmwares.create_firmware(org, filepath) do
      firmware = Repo.preload(firmware, :product)

      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.api_firmware_path(conn, :show, org, product.name, firmware.uuid)
      )
      |> render(:show, firmware: firmware)
    else
      {nil, %{}} -> {:error, {:no_firmware_uploaded, "No firmware uploaded"}}
      error -> error
    end
  end

  operation(:show,
    summary: "Show a Firmware",
    parameters: [
      org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
      product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"],
      uuid: [in: :path, description: "Firmware UUID", type: :string, example: "d9f8c63a-1234-5678-abcd-ef0123456789"]
    ],
    responses:
      [
        ok: {"Firmware response", "application/json", FirmwareSchemas.FirmwareResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def show(%{assigns: %{product: product}} = conn, %{"uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid) do
      render(conn, :show, firmware: firmware)
    end
  end

  operation(:delete,
    summary: "Delete a Firmware",
    parameters: [
      org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
      product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"],
      uuid: [in: :path, description: "Firmware UUID", type: :string, example: "d9f8c63a-1234-5678-abcd-ef0123456789"]
    ],
    responses:
      [
        no_content: "Empty response",
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def delete(%{assigns: %{product: product}} = conn, %{"uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid),
         {:ok, _} <- Firmwares.delete_firmware(firmware) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:download,
    summary: "Download a Firmware",
    parameters: [
      org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
      product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"],
      uuid: [in: :path, description: "Firmware UUID", type: :string, example: "d9f8c63a-1234-5678-abcd-ef0123456789"]
    ],
    responses:
      [
        found: "Redirect to firmware download URL",
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def download(%{assigns: %{product: product}} = conn, %{"uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid),
         {:ok, url} <- Application.get_env(:nerves_hub, :firmware_upload).download_file(firmware) do
      redirect(conn, external: url)
    end
  end
end
