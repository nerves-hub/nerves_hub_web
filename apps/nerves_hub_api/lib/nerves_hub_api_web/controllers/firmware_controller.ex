defmodule NervesHubAPIWeb.FirmwareController do
  use NervesHubAPIWeb, :controller

  alias NervesHubCore.Firmwares
  alias NervesHubCore.Firmwares.Firmware

  action_fallback(NervesHubAPIWeb.FallbackController)

  def index(%{assigns: %{product: product}} = conn, _params) do
    firmwares = Firmwares.get_firmwares_by_product(product.id)
    render(conn, "index.json", firmwares: firmwares)
  end

  def create(%{assigns: %{org: org, org_limit: org_limit, product: product}} = conn, _params) do
    %{firmware_size: size_limit} = org_limit

    with {:ok, filepath, conn} <- read_firmware(conn, size_limit),
         {:ok, firmware_params} <- Firmwares.prepare_firmware_params(org, filepath),
         {:ok, firmware} <- Firmwares.create_firmware(firmware_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", firmware_path(conn, :show, org, product, firmware))
      |> render("show.json", firmware: firmware)
    end
  end

  def show(%{assigns: %{org: org}} = conn, %{"uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_uuid(org, uuid) do
      render(conn, "show.json", firmware: firmware)
    end
  end

  def delete(%{assigns: %{org: org}} = conn, %{"uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_uuid(org, uuid),
         {:ok, %Firmware{}} <- Firmwares.delete_firmware(firmware) do
      send_resp(conn, :no_content, "")
    end
  end

  defp read_firmware(_, _, _ \\ 0, _ \\ "")

  defp read_firmware(_conn, size_limit, size, _buffer) when size >= size_limit do
    {:error, "Firmware exceeds size limit of #{size_limit} bytes"}
  end

  defp read_firmware(conn, size_limit, size, buffer) do
    case Plug.Conn.read_body(conn) do
      {:more, data, conn} ->
        size = byte_size(data) + size
        read_firmware(conn, size_limit, size, buffer <> data)

      {:ok, data, conn} ->
        size = byte_size(data) + size

        if size >= size_limit do
          {:error, "Firmware exceeds size limit of #{size_limit} bytes"}
        else
          content = buffer <> data

          case byte_size(content) do
            0 ->
              {:error, "invalid byte length"}

            _ ->
              filepath = Plug.Upload.random_file!("firmware")
              File.write!(filepath, content)
              {:ok, filepath, conn}
          end
        end

      error ->
        error
    end
  end
end
