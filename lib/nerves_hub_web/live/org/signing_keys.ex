defmodule NervesHubWeb.Live.Org.SigningKeys do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    {:ok, assign(socket, :org, scope.org)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> page_title("Signing Keys - #{socket.assigns.org.name}")
    |> assign(:signing_keys, list_signing_keys(socket.assigns.current_scope))
    |> sidebar_tab(:signing_keys)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> page_title("New Signing Key - #{socket.assigns.org.name}")
    |> assign(:form, to_form(Accounts.OrgKey.changeset(%Accounts.OrgKey{}, %{})))
    |> sidebar_tab(:signing_keys)
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"org_key" => key_params}, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"signing_key:create", scope)

    params =
      key_params
      |> Enum.into(%{"org_id" => scope.org.id})
      |> Enum.into(%{"created_by_id" => scope.user.id})

    case Accounts.create_org_key(params) do
      {:ok, _org_key} ->
        {:noreply,
         socket
         |> put_flash(:info, "Signing Key created successfully.")
         |> push_navigate(to: ~p"/org/#{scope.org}/settings/keys")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"signing_key_id" => signing_key_id}, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"signing_key:delete", scope)

    {:ok, signing_key} = Accounts.get_org_key(scope, signing_key_id)

    case Accounts.delete_org_key(signing_key) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Signing Key deleted successfully.")
         |> assign(:signing_keys, list_signing_keys(scope))}

      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          changeset.errors
          |> Enum.map_join(", ", fn {_k, v} -> elem(v, 0) end)

        {:noreply, put_flash(socket, :error, "Error deleting Signing Key : " <> message)}
    end
  end

  defp list_signing_keys(scope), do: Accounts.list_org_keys(scope)
end
