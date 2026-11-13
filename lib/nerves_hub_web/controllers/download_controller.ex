defmodule NervesHubWeb.DownloadController do
  use NervesHubWeb, :controller

  alias NervesHub.Archives
  alias NervesHub.Firmwares
  alias NervesHubWeb.Helpers.Authorization

  plug(:validate_role, [org: :view] when action in [:archive])
  # The permission the firmware page's download button checks, so a custom
  # role that grants it can use the button.
  plug(:require_firmware_download when action in [:firmware])

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

  defp require_firmware_download(%{assigns: %{current_scope: scope}} = conn, _opts) do
    Authorization.authorized!(:"firmware:download", scope)
    conn
  end

  defp firmware_uploader(), do: Application.get_env(:nerves_hub, :firmware_upload)
end
