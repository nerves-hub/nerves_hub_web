defmodule NervesHubWeb.API.FirmwareController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Firmwares

  action_fallback(NervesHubWeb.API.FallbackController)

  plug(:validate_role, [org: :delete] when action in [:delete])
  plug(:validate_role, [org: :write] when action in [:create])
  plug(:validate_role, [org: :read] when action in [:index, :show])

  def index(%{assigns: %{product: product}} = conn, _params) do
    firmwares = Firmwares.get_firmwares_by_product(product.id)
    render(conn, "index.json", firmwares: firmwares)
  end

  def create(%{assigns: %{org: org, product: product}} = conn, params) do
    params = whitelist(params, [:firmware])

    with {%{path: filepath}, _params} <- Map.pop(params, :firmware),
         {:ok, firmware} <- Firmwares.create_firmware(org, filepath) do
      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.firmware_path(conn, :show, org, product.name, firmware.uuid)
      )
      |> render("show.json", firmware: firmware)
    else
      {nil, %{}} -> {:error, :no_firmware_uploaded}
      error -> error
    end
  end

  def show(%{assigns: %{product: product}} = conn, %{"uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid) do
      render(conn, "show.json", firmware: firmware)
    end
  end

  def delete(%{assigns: %{product: product}} = conn, %{"uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid),
         {:ok, _} <- Firmwares.delete_firmware(firmware) do
      send_resp(conn, :no_content, "")
    end
  end
end
