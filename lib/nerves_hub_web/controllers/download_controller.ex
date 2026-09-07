defmodule NervesHubWeb.DownloadController do
  use NervesHubWeb, :controller

  alias NervesHub.Archives
  alias NervesHub.Firmwares

  plug(:validate_role, org: :view)

  def archive(%{assigns: %{current_scope: scope}} = conn, %{"uuid" => uuid}) do
    case Archives.get(scope.product, uuid) do
      {:ok, archive} ->
        redirect(conn, external: Archives.url(archive))

      {:error, :not_found} ->
        raise NervesHubWeb.NotFoundError
    end
  end

  def firmware(%{assigns: %{current_scope: scope}} = conn, %{"uuid" => uuid}) do
    case Firmwares.get_firmware_by_product_and_uuid(scope.product, uuid) do
      {:ok, firmware} ->
        {:ok, url} = firmware_uploader().download_file(firmware)

        redirect(conn, external: url)

      {:error, :not_found} ->
        raise NervesHubWeb.NotFoundError
    end
  end

  defp firmware_uploader(), do: Application.get_env(:nerves_hub, :firmware_upload)
end
