defmodule NervesHubWeb.Live.Org.Settings do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> page_title("Settings - #{socket.assigns.org.name}")
      |> assign(:form, to_form(Org.changeset(socket.assigns.org, %{})))

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("update", %{"org" => org_params}, socket) do
    authorized!(:"organization:update", socket.assigns.org_user)

    case Accounts.update_org(socket.assigns.org, org_params) do
      {:ok, org} ->
        socket
        |> put_flash(:info, "Organization updated")
        |> push_navigate(to: ~p"/orgs/#{hashid(org)}/settings")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end
end
