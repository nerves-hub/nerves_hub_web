defmodule NervesHubWeb.Live.Org.Settings do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> page_title("Settings - #{socket.assigns.org.name}")
      |> assign(:form, to_form(Org.changeset(socket.assigns.org, %{})))

    {:ok, socket}
  end

  @impl true
  def handle_event("update", %{"org" => org_params}, socket) do
    authorized!(:update_organization, socket.assigns.org_user)

    case Accounts.update_org(socket.assigns.org, org_params) do
      {:ok, org} ->
        socket
        |> put_flash(:info, "Organization updated")
        |> push_navigate(to: ~p"/org/#{org.name}/settings")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end
end
