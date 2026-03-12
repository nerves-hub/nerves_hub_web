defmodule NervesHubWeb.Live.Org.Settings do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org

  @impl Phoenix.LiveView
  @decorate requires_permission(:"organization:update")
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    socket
    |> page_title("Settings - #{scope.org.name}")
    |> assign(:org, scope.org)
    |> assign(:form, to_form(Org.changeset(scope.org)))
    |> sidebar_tab(:settings)
    |> ok()
  end

  @impl Phoenix.LiveView
  @decorate requires_permission(:"organization:update")
  def handle_event("update", %{"org" => org_params}, socket) do
    scope = socket.assigns.current_scope
    authorized!(:"organization:update", scope)

    case Accounts.update_org(scope.org, org_params) do
      {:ok, org} ->
        socket
        |> put_flash(:info, "Organization updated")
        |> push_navigate(to: ~p"/org/#{org}/settings")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end
end
