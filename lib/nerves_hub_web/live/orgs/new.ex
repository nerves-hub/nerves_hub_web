defmodule NervesHubWeb.Live.Orgs.New do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts

  def mount(_params, _session, socket) do
    changeset = Accounts.Org.creation_changeset(%Accounts.Org{}, %{})

    socket =
      socket
      |> assign(:page_title, "New Organization")
      |> assign(:form, to_form(changeset))

    {:ok, socket}
  end

  def handle_event("save_org", %{"org" => org_params}, socket) do
    params = org_params |> whitelist([:name])

    case Accounts.create_org(socket.assigns.user, params) do
      {:ok, org} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization created successfully.")
         |> push_navigate(to: ~p"/org/#{org.name}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
