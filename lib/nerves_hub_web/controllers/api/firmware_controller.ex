defmodule NervesHubWeb.API.FirmwareController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.Firmwares
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.ErrorSchemas
  alias NervesHubWeb.API.Schemas.FirmwareSchemas

  require Logger

  plug(:require_membership when action in [:index, :show])
  plug(:require_every_device)
  plug(:require_permission, :"firmware:upload" when action in [:create])
  plug(:require_permission, :"firmware:download" when action in [:download])
  plug(:require_permission, :"firmware:delete" when action in [:delete])

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
    description: """
    Send the file as the `firmware` field of a `multipart/form-data` body.

    Accepts an fwup archive (`.fw`), an ESP-IDF application image (`.bin`), an
    AtomVM packbeam (`.avm`) or a RAUC verity bundle (`.raucb`). The format is
    determined from the file itself, not its name or extension.

    A product accepts only the formats listed in its `allowed_update_tools`,
    which is `["fwup"]` by default. ESP-IDF, AtomVM and RAUC each also have to
    be enabled for the platform, with `ESP_IDF_FIRMWARE_ENABLED`,
    `ATOMVM_FIRMWARE_ENABLED` or `RAUC_FIRMWARE_ENABLED`.

    **Firmware must be signed** against a key registered to the organization: an
    `ed25519` key for fwup and AtomVM, a `secure_boot_v2_rsa` key for ESP-IDF,
    or an `x509_certificate` key for RAUC.

    Two per-product settings excuse a *missing* signature, and nothing else.
    `allow_unsigned_esp_idf_firmware` accepts an ESP-IDF image with no signature
    block, and `allow_unsigned_atomvm_firmware` accepts a packbeam with no
    signature entry. Firmware that does carry a signature is always verified.
    fwup archives and RAUC bundles are always verified.

    The firmware's own metadata declares which product it belongs to, and that
    must match the product in the path.
    """,
    parameters: [
      org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
      product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"]
    ],
    request_body:
      {"Firmware file upload", "multipart/form-data", FirmwareSchemas.FirmwareUploadRequest, required: true},
    responses:
      [
        created: {"Firmware response", "application/json", FirmwareSchemas.FirmwareResponse},
        unprocessable_entity: {"Upload rejected", "application/json", FirmwareSchemas.FirmwareUploadErrorResponse}
      ] ++ @auth_error_responses
  )

  def create(%{assigns: %{current_scope: %{org: org}, product: product}} = conn, params) do
    Logger.info("System Memory:" <> inspect(:memsup.get_system_memory_data()))

    with {%{path: filepath}, _params} <- Map.pop(params, "firmware"),
         {:ok, firmware} <- Firmwares.create_firmware(org, filepath, product: product) do
      firmware = Firmwares.preload_product(firmware)

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

  def delete(%{assigns: %{current_scope: scope, product: product}} = conn, %{"uuid" => uuid}) do
    actor = Scope.actor(scope)

    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid),
         {:ok, _} <- Firmwares.delete_firmware(firmware, actor) do
      _ = ProductTemplates.audit_firmware_deleted(actor, product, firmware)

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
