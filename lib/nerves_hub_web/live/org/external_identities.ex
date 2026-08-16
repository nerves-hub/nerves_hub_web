defmodule NervesHubWeb.Live.Org.ExternalIdentities do
  @moduledoc """
  The keys an organisation's devices and people hold on networks NervesHub does
  not run.

  Behind `org_iroh_endpoints_ui_enabled?/0`, which is off unless a deployment says
  otherwise. The check is repeated in the router: hiding a link in the sidebar
  leaves the URL typeable, so the mount refuses as well.

  Registering a key here records one nobody has proven — which is the point, for
  a laptop or a device that has not connected yet, and also the risk. A key
  belonging to someone else would place their machine on this organisation's
  network, so the context refuses one already recorded anywhere, and it takes
  the `manage` role to try.
  """

  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Devices.ExternalIdentities
  alias NervesHub.Devices.ExternalIdentity

  # The page is named for iroh because that is what the keys are used for today.
  # The table underneath is not iroh-specific, so this is the one place that
  # decides which protocol the page is about.
  @service :iroh

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    if org_iroh_endpoints_ui_enabled?() do
      {:ok,
       socket
       |> assign(:org, scope.org)
       |> assign(:service, @service)
       |> assign(:search, "")
       |> assign(:owner_filter, nil)
       |> assign(:form, registration_form())
       |> assign(:registering, false)
       |> assign(:members, member_options(scope.org))
       |> load_identities()}
    else
      # Same answer as a page that does not exist, rather than one that admits
      # it is switched off.
      raise NervesHubWeb.NotFoundError
    end
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> page_title("Iroh Endpoints - #{socket.assigns.org.name}")
     |> sidebar_tab(:external_identities)}
  end

  @impl Phoenix.LiveView
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> load_identities()}
  end

  def handle_event("filter", %{"owner" => owner}, socket) do
    {:noreply, socket |> assign(:owner_filter, cast_owner(owner)) |> load_identities()}
  end

  def handle_event("toggle-registration", _params, socket) do
    {:noreply,
     socket
     |> assign(:registering, not socket.assigns.registering)
     |> assign(:form, registration_form())}
  end

  def handle_event("register", %{"identity" => params}, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"external_identity:create", scope)

    case ExternalIdentities.register(scope.org.id, @service, params) do
      {:ok, _identity} ->
        {:noreply,
         socket
         |> put_flash(:info, "Endpoint registered.")
         |> assign(:registering, false)
         |> assign(:form, registration_form())
         |> load_identities()}

      {:error, :claimed_elsewhere} ->
        # Deliberately does not say where. Whether a key is registered in
        # another organisation is that organisation's business.
        {:noreply,
         put_flash(
           socket,
           :error,
           "That endpoint id is already registered. If it belongs to one of your devices, " <>
             "it will be claimed the next time that device connects."
         )}

      {:error, :invalid_member} ->
        # Only reachable by a crafted request: the select only ever offers this
        # organisation's members.
        {:noreply, put_flash(socket, :error, "That person is not in this organisation.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :identity))}
    end
  end

  def handle_event("delete", %{"id" => id}, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"external_identity:delete", scope)

    case ExternalIdentities.delete(scope.org.id, String.to_integer(id)) do
      {:ok, _identity} ->
        {:noreply,
         socket
         |> put_flash(:info, "Endpoint removed.")
         |> load_identities()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That endpoint could not be removed.")}
    end
  end

  defp load_identities(socket) do
    identities =
      ExternalIdentities.list_for_org(socket.assigns.org.id,
        service: @service,
        owner: socket.assigns.owner_filter,
        search: socket.assigns.search
      )

    assign(socket, :identities, identities)
  end

  defp registration_form() do
    to_form(ExternalIdentity.changeset(%ExternalIdentity{}, %{}), as: :identity)
  end

  # Memberships rather than users, since that is what an identity attaches to:
  # the same person in two organisations holds a separate key in each.
  defp member_options(org) do
    org
    |> Accounts.get_org_users()
    |> Enum.map(&{&1.user.name, &1.id})
  end

  defp cast_owner("device"), do: :device
  defp cast_owner("org_user"), do: :org_user
  defp cast_owner("unowned"), do: :unowned
  defp cast_owner(_owner), do: nil

  @doc false
  # What holds this key, for the table. A device and a membership are the two
  # owners; anything else was recorded by hand and belongs to the organisation.
  def owner_label(%ExternalIdentity{device: %{identifier: identifier}}), do: {"Device", identifier}

  def owner_label(%ExternalIdentity{org_user: %{user: %{name: name}}}), do: {"User", name}

  def owner_label(%ExternalIdentity{}), do: {"Unassigned", "registered by hand"}
end
