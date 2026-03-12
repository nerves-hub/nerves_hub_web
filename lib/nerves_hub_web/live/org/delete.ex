defmodule NervesHubWeb.Live.Org.Delete do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts

  @impl Phoenix.LiveView
  @decorate requires_permission(:"organization:delete")
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    socket
    |> page_title("Delete Organization - #{scope.org.name}")
    |> assign(:org, scope.org)
    |> assign(:form, to_form(%{}))
    |> sidebar_tab(:settings)
    |> ok()
  end

  @impl Phoenix.LiveView
  @decorate requires_permission(:"organization:delete")
  def handle_event("delete", params, socket) do
    scope = socket.assigns.current_scope
    authorized!(:"organization:delete", scope)

    if params["confirm_name"] == scope.org.name do
      case Accounts.soft_delete_org(scope.org) do
        {:ok, _org} ->
          socket
          |> put_flash(:info, "The Organization #{scope.org.name} has successfully been deleted")
          |> push_navigate(to: ~p"/orgs")
          |> noreply()

        {:error, _changeset} ->
          socket
          |> put_flash(
            :error,
            "There was an error deleting the Organization #{scope.org.name}. Please contact support."
          )
          |> noreply()
      end
    else
      socket
      |> put_flash(:error, "Please type #{scope.org.name} to confirm.")
      |> noreply()
    end
  end
end
