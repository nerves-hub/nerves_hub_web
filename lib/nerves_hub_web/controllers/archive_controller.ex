defmodule NervesHubWeb.ArchiveController do
  use NervesHubWeb, :controller

  alias NervesHub.Archives

  plug(:validate_role, org: :view)

  def download(conn, %{"uuid" => uuid}) do
    %{product: product} = conn.assigns

    {:ok, archive} = Archives.get(product, uuid)

    redirect(conn, external: Archives.url(archive))
  end
end
