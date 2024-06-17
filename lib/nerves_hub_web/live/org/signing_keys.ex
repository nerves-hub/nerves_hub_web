defmodule NervesHubWeb.Live.Org.SigningKeys do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "#{socket.assigns.org.name} / Signing Keys")
      |> assign(:signing_keys, list_signing_keys(socket.assigns.org))

    {:ok, socket}
  end

  def handle_event("delete", %{"signing_key_id" => signing_key_id}, socket) do
    authorized!(:delete_signing_key, socket.assigns.org_user)

    {:ok, signing_key} = Accounts.get_org_key(socket.assigns.org, signing_key_id)

    with {:ok, _} <- Accounts.delete_org_key(signing_key) do
      {:noreply, assign(socket, :signing_keys, list_signing_keys(socket.assigns.org))}
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
