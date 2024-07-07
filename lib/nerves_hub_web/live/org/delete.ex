defmodule NervesHubWeb.Live.Org.Delete do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> page_title("Delete Organization - #{socket.assigns.org.name}")
    |> assign(:form, to_form(%{}))
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("delete", params, socket) do
    authorized!(:"organization:delete", socket.assigns.org_user)

    if params["confirm_name"] == socket.assigns.org.name do
      case Accounts.soft_delete_org(socket.assigns.org) do
        {:ok, _org} ->
          socket
          |> put_flash(
            :info,
            "The Organization #{socket.assigns.org.name} has successfully been deleted"
          )
          |> push_navigate(to: ~p"/orgs")
          |> noreply()

        {:error, _changeset} ->
          socket
          |> put_flash(
            :error,
            "There was an error deleting the Organization #{socket.assigns.org.name}. Please contact support."
          )
          |> noreply()
      end
    else
      socket
      |> put_flash(:error, "Please type #{socket.assigns.org.name} to confirm.")
      |> noreply()
    end
  end
end
