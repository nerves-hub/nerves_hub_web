defmodule NervesHubWeb.Live.Org.SigningKeys do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> page_title("Signing Keys - #{socket.assigns.org.name}")
    |> assign(:signing_keys, list_signing_keys(socket.assigns.org))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> page_title("New Signing Key - #{socket.assigns.org.name}")
    |> assign(:form, to_form(Accounts.OrgKey.changeset(%Accounts.OrgKey{}, %{})))
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"org_key" => key_params}, socket) do
    authorized!(:"signing_key:create", socket.assigns.org_user)

    params =
      key_params
      |> Enum.into(%{"org_id" => socket.assigns.org.id})
      |> Enum.into(%{"created_by_id" => socket.assigns.user.id})

    case Accounts.create_org_key(params) do
      {:ok, _org_key} ->
        {:noreply,
         socket
         |> put_flash(:info, "Signing Key created successfully.")
         |> push_navigate(to: ~p"/org/#{socket.assigns.org.name}/settings/keys")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"signing_key_id" => signing_key_id}, socket) do
    authorized!(:"signing_key:delete", socket.assigns.org_user)

    {:ok, signing_key} = Accounts.get_org_key(socket.assigns.org, signing_key_id)

    with {:ok, _} <- Accounts.delete_org_key(signing_key) do
      {:noreply,
       socket
       |> put_flash(:info, "Signing Key deleted successfully.")
       |> assign(:signing_keys, list_signing_keys(socket.assigns.org))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          changeset.errors
          |> Enum.map(fn {_k, v} -> elem(v, 0) end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Error deleting Signing Key : " <> message)}
    end
  end

  defp list_signing_keys(org), do: Accounts.list_org_keys(org)
end
