defmodule NervesHubWeb.Live.SupportScripts.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Scripts
  alias NervesHub.Repo

  def mount(_params, _session, socket) do
    socket
    |> page_title("Support Scripts - #{socket.assigns.product.name}")
    |> assign(:scripts, Scripts.all_by_product(socket.assigns.product))
    |> ok()
  end

  def handle_event("delete-support-script", %{"script_id" => script_id}, socket) do
    authorized!(:"support_script:delete", socket.assigns.org_user)

    %{product: product} = socket.assigns

    {:ok, script} = Scripts.get(product, script_id)

    Repo.delete!(script)

    socket
    |> put_flash(:info, "Script deleted")
    |> assign(:scripts, Scripts.all_by_product(socket.assigns.product))
    |> noreply()
  end
end
