defmodule NervesHubWeb.Live.Org.Settings do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    socket
    |> page_title("Settings - #{scope.org.name}")
    |> assign(:org, scope.org)
    |> assign(:form, to_form(Org.changeset(scope.org)))
    |> sidebar_tab(:settings)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("update", %{"org" => org_params}, %{assigns: %{current_scope: scope}} = socket) do
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
