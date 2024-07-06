defmodule NervesHubWeb.DownloadController do
  use NervesHubWeb, :controller

  alias NervesHub.Archives
  alias NervesHub.Firmwares

  plug(:validate_role, org: :view)

  def archive(%{assigns: %{product: product}} = conn, %{"uuid" => uuid}) do
    {:ok, archive} = Archives.get(product, uuid)

    redirect(conn, external: Archives.url(archive))
  end

  def firmware(%{assigns: %{product: product}} = conn, %{"uuid" => uuid}) do
    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(product, uuid)

    {:ok, url} = firmware_uploader().download_file(firmware)

    redirect(conn, external: url)
  end

  defp firmware_uploader(), do: Application.get_env(:nerves_hub, :firmware_upload)
end
