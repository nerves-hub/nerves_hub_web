defmodule NervesHubWeb.API.FirmwareController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Firmwares
  alias NervesHub.Repo

  require Logger

  plug(:validate_role, [org: :manage] when action in [:create, :delete])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  tags(["Firmwares"])
  security([%{}, %{"bearer_auth" => []}])

  operation(:index,
    summary: "List all Firmwares for a Product"
  )

  def index(%{assigns: %{product: product}} = conn, _params) do
    firmwares = Firmwares.get_firmwares_by_product(product.id)
    render(conn, :index, firmwares: firmwares)
  end

  operation(:create,
    summary: "Upload a Firmware for a Product"
  )

  def create(%{assigns: %{org: org, product: product}} = conn, params) do
    params = whitelist(params, [:firmware])

    Logger.info("System Memory:" <> inspect(:memsup.get_system_memory_data()))

    with {%{path: filepath}, _params} <- Map.pop(params, :firmware),
         {:ok, firmware} <- Firmwares.create_firmware(org, filepath),
         firmware <- Repo.preload(firmware, :product) do
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
    summary: "Show a Firmware"
  )

  def show(%{assigns: %{product: product}} = conn, %{"uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid) do
      render(conn, :show, firmware: firmware)
    end
  end

  operation(:delete,
    summary: "Delete a Firmware"
  )

  def delete(%{assigns: %{product: product}} = conn, %{"uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid),
         {:ok, _} <- Firmwares.delete_firmware(firmware) do
      send_resp(conn, :no_content, "")
    end
  end
end
