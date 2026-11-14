defmodule NervesHubWeb.DownloadController do
  use NervesHubWeb, :controller

  alias NervesHub.Archives
  alias NervesHub.Firmwares
  alias NervesHubWeb.Helpers.Authorization

  # The permissions the archive and firmware pages' download buttons check,
  # so a custom role that grants one can use its button.
  plug(:require_permission, [permission: :"archive:download"] when action in [:archive])
  plug(:require_permission, [permission: :"firmware:download"] when action in [:firmware])

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

  defp require_permission(%{assigns: %{current_scope: scope}} = conn, permission: permission) do
    Authorization.authorized!(permission, scope)
    conn
  end

  defp firmware_uploader(), do: Application.get_env(:nerves_hub, :firmware_upload)
end
