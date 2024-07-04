defmodule NervesHubWeb.FirmwareController do
  use NervesHubWeb, :controller

  alias NervesHub.Firmwares

  plug(:validate_role, org: :view)

  def download(%{assigns: %{product: product}} = conn, %{"firmware_uuid" => uuid}) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid) do
      if uploader = Application.get_env(:nerves_hub, :firmware_upload) do
        uploader.download_file(firmware)
        |> case do
          {:ok, url} ->
            redirect(conn, external: url)

          error ->
            error
        end
      else
        {:error}
      end
    end
  end
end
