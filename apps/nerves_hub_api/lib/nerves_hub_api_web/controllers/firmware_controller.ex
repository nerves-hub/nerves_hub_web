defmodule NervesHubAPIWeb.FirmwareController do
  use NervesHubAPIWeb, :controller
  alias NervesHubCore.Firmwares

  action_fallback(NervesHubAPIWeb.FallbackController)

  def index(%{assigns: %{product: product}} = conn, _params) do
    firmwares = Firmwares.get_firmwares_by_product(product.id)
    render(conn, "index.json", firmwares: firmwares)
  end

  def create(%{assigns: %{org: org, product: product}} = conn, params) do
    params = whitelist(params, [:ttl, :firmware])

    with {%{path: filepath}, params} <- Map.pop(params, :firmware),
         {:ok, firmware} <- Firmwares.create_firmware(org, filepath, params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", firmware_path(conn, :show, org, product, firmware))
      |> render("show.json", firmware: firmware)
    else
      {nil, %{}} -> {:error, :no_firmware_uploaded}
      error -> error
    end
  end

  def show(%{assigns: %{org: org}} = conn, %{"uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_uuid(org, uuid) do
      render(conn, "show.json", firmware: firmware)
    end
  end

  def delete(%{assigns: %{org: org}} = conn, %{"uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_uuid(org, uuid),
         :ok <- Firmwares.delete_firmware(firmware) do
      send_resp(conn, :no_content, "")
    end
  end
end
